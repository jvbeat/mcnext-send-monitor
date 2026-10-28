/**
 * Checks WhatsApp and SMS sends in Data Cloud (ssot__MessageEngagement__dlm).
 *
 * Per content, it compares send attempts with rejections in the window. Content or platform errors above
 * the minimum, or a small send rejected entirely by the Meta template, ask to fix the content. Audience
 * errors above the minimum and the ratio ask to review the segment. It also reads the parameters of the
 * messages that went out: when one value fills a large share of a variable that otherwise varies, or a
 * large share of the messages carries one of the configured default texts, the people who got it have no
 * data for the field.
 */
public with sharing class SendMonitorMessageCheck {

    private static final String SEND = 'SEND_STATUS';
    private static final String DELIVERY = 'DR';
    private static final Pattern TYPED_VARIABLE = Pattern.compile('(\\{\\{[^}]*\\}\\}|\\{![^}]*\\})');
    private static final Pattern META_COUNT = Pattern.compile('localizable_params \\((\\d+)\\) does not match the expected number of params \\((\\d+)\\)');
    private static final Pattern PARAMETERS = Pattern.compile('"parameters"\\s*:\\s*\\[(.*?)\\]');
    private static final Pattern TEXT_VALUE = Pattern.compile('"text"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"');

    /** Attempts and rejections of one content in the window. */
    public class Situation {
        public String content;
        public String channel;
        public Integer attempts = 0;
        public Map<String, Integer> rejectionsByCode = new Map<String, Integer>();
        public Map<String, String> messageByCode = new Map<String, String>();
        public String sample;

        public Integer rejections(SendMonitorRules rules, Set<String> categories) {
            Integer total = 0;
            for (String code : rejectionsByCode.keySet()) {
                if (categories.contains(rules.category(code, messageByCode.get(code)))) {
                    total += rejectionsByCode.get(code);
                }
            }
            return total;
        }
    }

    /**
     * @param now end of the window
     * @param rules code classification
     * @return alerts for the window, without checking repetition
     */
    public static List<SendMonitorAlert> run(Datetime now, SendMonitorRules rules) {
        Datetime since = now.addHours(-SendMonitorConfig.windowHours());
        String day = SendMonitorConfig.day(now);
        Map<String, Situation> situations = group(SendMonitorSource.sql('messageStatus', statusSql(since)));
        Map<String, Map<String, Map<String, Integer>>> values = parameterValues(SendMonitorSource.sql('messageTexts', textSql(since)));

        Set<String> keys = new Set<String>(situations.keySet());
        keys.addAll(values.keySet());
        Map<String, String> names = SendMonitorSource.contentNames(keys);

        List<SendMonitorAlert> alerts = new List<SendMonitorAlert>();
        for (Situation situation : situations.values()) {
            alerts.addAll(alertsFor(situation, names.get(situation.content), day, rules));
        }
        for (String content : values.keySet()) {
            Situation situation = situations.get(content);
            SendMonitorAlert alert = missingData(content, situation == null ? null : situation.channel, names.get(content), values.get(content), day);
            if (alert != null) {
                alerts.add(alert);
            }
        }
        return alerts;
    }

    @TestVisible
    private static List<SendMonitorAlert> alertsFor(Situation situation, String name, String day, SendMonitorRules rules) {
        List<SendMonitorAlert> alerts = new List<SendMonitorAlert>();
        String title = titleOf(situation.content, name);
        String channel = channelLabel(situation.channel);
        Integer hours = SendMonitorConfig.windowHours();

        Set<String> serious = new Set<String>{ SendMonitorRules.CONTENT, SendMonitorRules.PLATFORM };
        Integer seriousCount = situation.rejections(rules, serious);
        if (seriousCount >= SendMonitorConfig.minContentErrors() || rejectedByTemplate(situation)) {
            String body = String.format(System.Label.SM_Content_Body, new List<Object>{ seriousCount, situation.attempts, title, hours })
                + '\n\n' + details(situation, serious, rules)
                + typedVariable(situation.sample)
                + '\n' + System.Label.SM_Content_Action;
            alerts.add(new SendMonitorAlert(SendMonitor.TYPE_CONTENT, situation.content, day,
                String.format(System.Label.SM_Content_Title, new List<Object>{ channel, title }), body));
        }

        Set<String> audience = new Set<String>{ SendMonitorRules.AUDIENCE };
        Integer audienceCount = situation.rejections(rules, audience);
        if (audienceCount >= SendMonitorConfig.minAudienceErrors() && situation.attempts > 0
            && Decimal.valueOf(audienceCount) / situation.attempts >= SendMonitorConfig.audienceRatio()) {
            String body = String.format(System.Label.SM_Audience_Body, new List<Object>{ audienceCount, situation.attempts, title, hours })
                + '\n\n' + details(situation, audience, rules)
                + '\n' + System.Label.SM_Audience_Action;
            alerts.add(new SendMonitorAlert(SendMonitor.TYPE_AUDIENCE, situation.content, day,
                String.format(System.Label.SM_Audience_Title, new List<Object>{ channel, title }), body));
        }
        return alerts;
    }

    /**
     * A small send, such as one step of a journey, does not reach the minimum, but a Meta template error
     * on every attempt is a content error and not a problem of the person.
     */
    @TestVisible
    private static Boolean rejectedByTemplate(Situation situation) {
        Integer byTemplate = 0;
        for (String code : situation.rejectionsByCode.keySet()) {
            if (code != null && code.startsWith('WA-132')) {
                byTemplate += situation.rejectionsByCode.get(code);
            }
        }
        return byTemplate > 0 && byTemplate >= situation.attempts;
    }

    private static String details(Situation situation, Set<String> categories, SendMonitorRules rules) {
        String text = '';
        for (String code : situation.rejectionsByCode.keySet()) {
            String message = situation.messageByCode.get(code);
            if (!categories.contains(rules.category(code, message))) {
                continue;
            }
            String explanation = rules.explanation(code, message);
            if (code == 'WA-132000') {
                explanation += metaCount(message);
            }
            text += String.format(System.Label.SM_Detail_Line, new List<Object>{
                situation.rejectionsByCode.get(code), code == null ? System.Label.SM_No_Code : code, explanation
            }) + '\n';
        }
        return text;
    }

    /**
     * When the rejected message carries a variable that was typed as text, the text shows in the payload.
     * A variable linked through the field selector shows as an expression of the platform (@root) and is
     * not reported.
     */
    @TestVisible
    private static String typedVariable(String sample) {
        if (String.isBlank(sample)) {
            return '';
        }
        Matcher found = TYPED_VARIABLE.matcher(sample);
        if (!found.find() || found.group(1).contains('@root')) {
            return '';
        }
        return '\n' + String.format(System.Label.SM_Typed_Variable, new List<Object>{ found.group(1) }) + '\n';
    }

    /**
     * @param message Meta message for WA-132000
     * @return what to fix, from the counts Meta reported, or blank
     */
    @TestVisible
    private static String metaCount(String message) {
        if (String.isBlank(message)) {
            return '';
        }
        Matcher count = META_COUNT.matcher(message);
        if (!count.find()) {
            return '';
        }
        Integer sent = Integer.valueOf(count.group(1));
        Integer expected = Integer.valueOf(count.group(2));
        if (expected == 0) {
            return String.format(System.Label.SM_Meta_Count_None, new List<Object>{ sent });
        }
        return String.format(System.Label.SM_Meta_Count, new List<Object>{ sent, expected });
    }

    /**
     * @param content content key
     * @param channel channel of the content, or null
     * @param name content name, or null
     * @param counts value counts by variable position, for the messages that went out
     * @param day day of the alert
     * @return the alert for the variable whose most frequent value looks like the default text, or null
     */
    @TestVisible
    private static SendMonitorAlert missingData(String content, String channel, String name, Map<String, Map<String, Integer>> counts, String day) {
        Integer total = counts.containsKey('') ? counts.get('').get('') : 0;
        if (total < SendMonitorConfig.fallbackMinSends()) {
            return null;
        }
        String worstPosition;
        String worstValue;
        Integer worstCount = 0;
        for (String position : counts.keySet()) {
            if (position == '') {
                continue;
            }
            Map<String, Integer> byValue = counts.get(position);
            String topValue;
            Integer topCount = 0;
            Integer filled = 0;
            for (String value : byValue.keySet()) {
                filled += byValue.get(value);
                if (byValue.get(value) > topCount) {
                    topCount = byValue.get(value);
                    topValue = value;
                }
            }
            Boolean known = topValue != null && SendMonitorConfig.fallbackValues().contains(topValue.trim().toLowerCase())
                && Decimal.valueOf(topCount) / filled >= SendMonitorConfig.fallbackRatio();
            if ((known || isFallback(topCount, filled, byValue.size())) && topCount > worstCount) {
                worstCount = topCount;
                worstValue = topValue;
                worstPosition = position;
            }
        }
        if (worstPosition == null) {
            return null;
        }
        String title = titleOf(content, name);
        String variable = '{{' + worstPosition.substringAfter('.') + '}}';
        return new SendMonitorAlert(SendMonitor.TYPE_MISSING_DATA, content, day,
            String.format(System.Label.SM_Missing_Data_Title, new List<Object>{ channelLabel(channel), title }),
            String.format(System.Label.SM_Missing_Data_Body, new List<Object>{ worstCount, total, title, worstValue, variable }));
    }

    /**
     * A personal field, such as the first name, is almost unique per person. When one value repeats in a
     * large share of the messages while the others stay almost unique, that value is the default text.
     * A field with few values by design, such as the name of the account manager, has repeated values on
     * the other side too and is not reported. The same value in every message is a fixed text.
     *
     * @param topCount messages with the most frequent value
     * @param filled messages with this variable
     * @param distinct distinct values of the variable
     * @return true when the most frequent value looks like the default text
     */
    @TestVisible
    private static Boolean isFallback(Integer topCount, Integer filled, Integer distinct) {
        Integer others = filled - topCount;
        if (others <= 0 || filled == 0) {
            return false;
        }
        Boolean largeShare = Decimal.valueOf(topCount) / filled >= SendMonitorConfig.fallbackRatio();
        Boolean othersAlmostUnique = Decimal.valueOf(distinct - 1) >= others * 0.5;
        return largeShare && othersAlmostUnique;
    }

    @TestVisible
    private static Map<String, Situation> group(List<Map<String, Object>> rows) {
        Map<String, Situation> situations = new Map<String, Situation>();
        for (Map<String, Object> row : rows) {
            String content = (String) row.get('content');
            if (String.isBlank(content)) {
                continue;
            }
            Situation situation = situations.get(content);
            if (situation == null) {
                situation = new Situation();
                situation.content = content;
                situations.put(content, situation);
            }
            String channel = (String) row.get('channel');
            if (String.isBlank(situation.channel) && String.isNotBlank(channel)) {
                situation.channel = channel;
            }
            Integer total = Integer.valueOf(String.valueOf(row.get('total')));
            Boolean isSend = (String) row.get('action') == SEND;
            if (isSend) {
                situation.attempts += total;
            }
            if (isSend && (String) row.get('status') == 'SENT') {
                continue;
            }
            String code = String.isBlank((String) row.get('code')) ? null : (String) row.get('code');
            Integer previous = situation.rejectionsByCode.containsKey(code) ? situation.rejectionsByCode.get(code) : 0;
            situation.rejectionsByCode.put(code, previous + total);
            situation.messageByCode.put(code, unescape((String) row.get('message')));
            String sample = (String) row.get('sample');
            if (String.isBlank(situation.sample) && String.isNotBlank(sample)) {
                situation.sample = unescape(sample);
            }
        }
        return situations;
    }

    /**
     * @param rows content and payload of each message that went out
     * @return per content, value counts by variable position ("component.index"); the blank position
     *         holds the number of messages read
     */
    @TestVisible
    private static Map<String, Map<String, Map<String, Integer>>> parameterValues(List<Map<String, Object>> rows) {
        Map<String, Map<String, Map<String, Integer>>> result = new Map<String, Map<String, Map<String, Integer>>>();
        for (Map<String, Object> row : rows) {
            String content = (String) row.get('content');
            String text = unescape((String) row.get('text'));
            if (String.isBlank(content) || String.isBlank(text)) {
                continue;
            }
            Map<String, Map<String, Integer>> counts = result.get(content);
            if (counts == null) {
                counts = new Map<String, Map<String, Integer>>{ '' => new Map<String, Integer>{ '' => 0 } };
                result.put(content, counts);
            }
            counts.get('').put('', counts.get('').get('') + 1);
            Matcher component = PARAMETERS.matcher(text);
            Integer componentIndex = 0;
            while (component.find()) {
                componentIndex++;
                Matcher value = TEXT_VALUE.matcher(component.group(1));
                Integer index = 0;
                while (value.find()) {
                    index++;
                    String position = componentIndex + '.' + index;
                    if (!counts.containsKey(position)) {
                        counts.put(position, new Map<String, Integer>());
                    }
                    Map<String, Integer> byValue = counts.get(position);
                    String found = value.group(1);
                    byValue.put(found, (byValue.containsKey(found) ? byValue.get(found) : 0) + 1);
                }
            }
        }
        return result;
    }

    /**
     * A rejected send shows in the send status; a delivery refused by Meta shows in the delivery receipt,
     * which does not carry the content and is joined to the send by the message Id.
     */
    @TestVisible
    private static String statusSql(Datetime since) {
        String start = timestamp(since);
        return 'SELECT e.ssot__EngagementAssetId__c AS content, MAX(e.ssot__EngagementChannelTypeId__c) AS channel, '
            + 'e.ssot__EngagementChannelActionId__c AS action, e.ssot__MessageRecipientSendStatus__c AS status, '
            + 'e.ssot__MessagingErrorCode__c AS code, COUNT(*) AS total, MAX(e.ssot__ErrorMessageText__c) AS message, '
            + 'MAX(e.ssot__MessageText__c) AS sample '
            + 'FROM ssot__MessageEngagement__dlm e '
            + 'WHERE e.ssot__EngagementChannelActionId__c = \'' + SEND + '\' AND e.ssot__EngagementDateTm__c >= ' + start + ' '
            + 'GROUP BY e.ssot__EngagementAssetId__c, e.ssot__EngagementChannelActionId__c, '
            + 'e.ssot__MessageRecipientSendStatus__c, e.ssot__MessagingErrorCode__c '
            + 'UNION ALL '
            + 'SELECT s.ssot__EngagementAssetId__c AS content, MAX(s.ssot__EngagementChannelTypeId__c) AS channel, '
            + 'd.ssot__EngagementChannelActionId__c AS action, d.ssot__MessageRecipientSendStatus__c AS status, '
            + 'd.ssot__MessagingErrorCode__c AS code, COUNT(*) AS total, MAX(d.ssot__ErrorMessageText__c) AS message, '
            + 'MAX(s.ssot__MessageText__c) AS sample '
            + 'FROM ssot__MessageEngagement__dlm d JOIN ssot__MessageEngagement__dlm s '
            + 'ON s.ssot__RecipientMessageId__c = d.ssot__RecipientMessageId__c AND s.ssot__EngagementChannelActionId__c = \'' + SEND + '\' '
            + 'WHERE d.ssot__EngagementChannelActionId__c = \'' + DELIVERY + '\' AND d.ssot__MessageRecipientSendStatus__c = \'FAILED\' '
            + 'AND d.ssot__EngagementDateTm__c >= ' + start + ' '
            + 'GROUP BY s.ssot__EngagementAssetId__c, d.ssot__EngagementChannelActionId__c, '
            + 'd.ssot__MessageRecipientSendStatus__c, d.ssot__MessagingErrorCode__c';
    }

    @TestVisible
    private static String textSql(Datetime since) {
        return 'SELECT ssot__EngagementAssetId__c AS content, ssot__MessageText__c AS text '
            + 'FROM ssot__MessageEngagement__dlm '
            + 'WHERE ssot__EngagementChannelActionId__c = \'' + SEND + '\' AND ssot__MessageRecipientSendStatus__c = \'SENT\' '
            + 'AND ssot__EngagementDateTm__c >= ' + timestamp(since) + ' LIMIT 10000';
    }

    public static String timestamp(Datetime moment) {
        return 'TIMESTAMP \'' + moment.formatGmt('yyyy-MM-dd HH:mm:ss') + '\'';
    }

    public static String channelLabel(String channel) {
        if (channel == 'SMS') {
            return System.Label.SM_Channel_SMS;
        }
        return System.Label.SM_Channel_WhatsApp;
    }

    private static String titleOf(String content, String name) {
        return String.isBlank(name) ? String.format(System.Label.SM_Unknown_Content, new List<Object>{ content }) : name;
    }

    public static String unescape(String text) {
        return text == null ? null : text.replace('&quot;', '"').replace('&#39;', '\'').replace('&amp;', '&');
    }
}
