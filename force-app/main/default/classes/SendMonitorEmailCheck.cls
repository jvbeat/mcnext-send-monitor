/**
 * Checks e-mail sends in Data Cloud (ssot__EmailEngagement__dlm).
 *
 * Per list e-mail, it compares send attempts with the messages not sent and their reason, and with the
 * hard bounces of the window. Reasons are classified by Send_Monitor_Code__mdt records with
 * Reason_Contains__c; an unknown reason counts as a platform problem.
 */
public with sharing class SendMonitorEmailCheck {

    private static final String SEND = 'SEND_STATUS';
    private static final String BOUNCE = 'BOUNCE';

    /** Attempts, messages not sent and hard bounces of one list e-mail in the window. */
    public class Situation {
        public String send;
        public Integer attempts = 0;
        public Integer sent = 0;
        public Integer hardBounces = 0;
        public Map<String, Integer> notSentByReason = new Map<String, Integer>();

        public Integer notSent(SendMonitorRules rules, Set<String> categories) {
            Integer total = 0;
            for (String reason : notSentByReason.keySet()) {
                if (categories.contains(rules.category(null, reason))) {
                    total += notSentByReason.get(reason);
                }
            }
            return total;
        }
    }

    /**
     * @param now end of the window
     * @param rules reason classification
     * @return alerts for the window, without checking repetition
     */
    public static List<SendMonitorAlert> run(Datetime now, SendMonitorRules rules) {
        Datetime since = now.addHours(-SendMonitorConfig.windowHours());
        Map<String, Situation> situations = group(SendMonitorSource.sql('emailStatus', statusSql(since)));
        Map<String, String> names = SendMonitorSource.listEmailNames(situations.keySet());
        List<SendMonitorAlert> alerts = new List<SendMonitorAlert>();
        String day = SendMonitorConfig.day(now);
        for (Situation situation : situations.values()) {
            alerts.addAll(alertsFor(situation, names.get(situation.send), day, rules));
        }
        return alerts;
    }

    @TestVisible
    private static List<SendMonitorAlert> alertsFor(Situation situation, String name, String day, SendMonitorRules rules) {
        List<SendMonitorAlert> alerts = new List<SendMonitorAlert>();
        String title = String.isBlank(name) ? situation.send : name;
        String channel = System.Label.SM_Channel_Email;
        Integer hours = SendMonitorConfig.windowHours();

        Set<String> serious = new Set<String>{ SendMonitorRules.CONTENT, SendMonitorRules.PLATFORM };
        Integer seriousCount = situation.notSent(rules, serious);
        if (seriousCount >= SendMonitorConfig.minContentErrors()) {
            alerts.add(new SendMonitorAlert(SendMonitor.TYPE_CONTENT, situation.send, day,
                String.format(System.Label.SM_Content_Title, new List<Object>{ channel, title }),
                String.format(System.Label.SM_Content_Body, new List<Object>{ seriousCount, situation.attempts, title, hours })
                    + '\n\n' + details(situation, serious, rules)
                    + '\n' + System.Label.SM_Content_Action));
        }

        Set<String> audience = new Set<String>{ SendMonitorRules.AUDIENCE };
        Integer audienceCount = situation.notSent(rules, audience);
        if (audienceCount >= SendMonitorConfig.minAudienceErrors() && situation.attempts > 0
            && Decimal.valueOf(audienceCount) / situation.attempts >= SendMonitorConfig.audienceRatio()) {
            alerts.add(new SendMonitorAlert(SendMonitor.TYPE_AUDIENCE, situation.send, day,
                String.format(System.Label.SM_Audience_Title, new List<Object>{ channel, title }),
                String.format(System.Label.SM_Audience_Body, new List<Object>{ audienceCount, situation.attempts, title, hours })
                    + '\n\n' + details(situation, audience, rules)
                    + '\n' + System.Label.SM_Audience_Action));
        }

        if (situation.hardBounces >= SendMonitorConfig.minAudienceErrors() && situation.sent > 0
            && Decimal.valueOf(situation.hardBounces) / situation.sent >= SendMonitorConfig.bounceRatio()) {
            Decimal percent = (Decimal.valueOf(situation.hardBounces) * 100 / situation.sent).setScale(1);
            alerts.add(new SendMonitorAlert(SendMonitor.TYPE_BOUNCES, situation.send, day,
                String.format(System.Label.SM_Bounce_Title, new List<Object>{ title }),
                String.format(System.Label.SM_Bounce_Body, new List<Object>{ situation.hardBounces, situation.sent, title, hours, percent })));
        }
        return alerts;
    }

    private static String details(Situation situation, Set<String> categories, SendMonitorRules rules) {
        String text = '';
        for (String reason : situation.notSentByReason.keySet()) {
            if (categories.contains(rules.category(null, reason))) {
                text += String.format(System.Label.SM_Email_Detail_Line, new List<Object>{
                    situation.notSentByReason.get(reason), rules.explanation(null, reason)
                }) + '\n';
            }
        }
        return text;
    }

    @TestVisible
    private static Map<String, Situation> group(List<Map<String, Object>> rows) {
        Map<String, Situation> situations = new Map<String, Situation>();
        for (Map<String, Object> row : rows) {
            String send = (String) row.get('send');
            if (String.isBlank(send)) {
                continue;
            }
            Situation situation = situations.get(send);
            if (situation == null) {
                situation = new Situation();
                situation.send = send;
                situations.put(send, situation);
            }
            Integer total = Integer.valueOf(String.valueOf(row.get('total')));
            String action = (String) row.get('action');
            String status = (String) row.get('status');
            if (action == BOUNCE) {
                if ((String) row.get('bounce') == 'HARD') {
                    situation.hardBounces += total;
                }
                continue;
            }
            if (status == 'TEST_SENT') {
                continue;
            }
            situation.attempts += total;
            if (status == 'SENT') {
                situation.sent += total;
                continue;
            }
            String reason = SendMonitorMessageCheck.unescape((String) row.get('reason'));
            String key = reason == null ? '' : reason;
            situation.notSentByReason.put(key, (situation.notSentByReason.containsKey(key) ? situation.notSentByReason.get(key) : 0) + total);
        }
        return situations;
    }

    @TestVisible
    private static String statusSql(Datetime since) {
        return 'SELECT ssot__BulkEmailMessageId__c AS send, ssot__EngagementChannelActionId__c AS action, '
            + 'ssot__EmailRecipientSendStatus__c AS status, ssot__EngagementActionReasonText__c AS reason, '
            + 'ssot__EmailBounceType__c AS bounce, COUNT(*) AS total '
            + 'FROM ssot__EmailEngagement__dlm '
            + 'WHERE ssot__EngagementChannelActionId__c IN (\'' + SEND + '\', \'' + BOUNCE + '\') '
            + 'AND ssot__EngagementDateTm__c >= ' + SendMonitorMessageCheck.timestamp(since) + ' '
            + 'GROUP BY ssot__BulkEmailMessageId__c, ssot__EngagementChannelActionId__c, ssot__EmailRecipientSendStatus__c, '
            + 'ssot__EngagementActionReasonText__c, ssot__EmailBounceType__c';
    }
}
