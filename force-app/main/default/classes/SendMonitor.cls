/**
 * Send monitor for Marketing Cloud Next: finds why sends did not reach people and tells the marketing team
 * what to fix.
 *
 * Each run reads the window that ends now and runs the checks the setting turns on: WhatsApp and SMS
 * sends, e-mail sends and flow runs. Each check runs on its own, so a failure in one is reported as an
 * alert and does not stop the others. The alerts go to SendMonitorNotifier, which records them and sends
 * the new ones.
 */
public with sharing class SendMonitor {

    public static final String TYPE_CONTENT = 'content';
    public static final String TYPE_AUDIENCE = 'audience';
    public static final String TYPE_MISSING_DATA = 'missing-data';
    public static final String TYPE_BOUNCES = 'bounces';
    public static final String TYPE_FLOW_FAILED = 'flow-failed';
    public static final String TYPE_FLOW_ERRORS = 'flow-errors';
    public static final String TYPE_FLOW_MISSED = 'flow-missed';
    public static final String TYPE_FLOW_PAUSED = 'flow-paused';
    public static final String TYPE_MONITOR_ERROR = 'monitor-error';

    public static final String CHECK_MESSAGES = 'messages';
    public static final String CHECK_EMAIL = 'email';
    public static final String CHECK_FLOWS = 'flows';

    /**
     * @param now end of the window
     * @return the alerts that were new and were sent
     */
    public static List<SendMonitorAlert> run(Datetime now) {
        Send_Monitor_Setting__mdt setting = SendMonitorConfig.setting();
        SendMonitorRules rules = new SendMonitorRules();
        List<SendMonitorAlert> alerts = new List<SendMonitorAlert>();
        if (setting.Check_Messages__c) {
            alerts.addAll(runCheck(CHECK_MESSAGES, now, rules));
        }
        if (setting.Check_Email__c) {
            alerts.addAll(runCheck(CHECK_EMAIL, now, rules));
        }
        if (setting.Check_Flows__c) {
            alerts.addAll(runCheck(CHECK_FLOWS, now, rules));
        }
        return SendMonitorNotifier.send(alerts);
    }

    private static List<SendMonitorAlert> runCheck(String check, Datetime now, SendMonitorRules rules) {
        try {
            if (check == CHECK_MESSAGES) {
                return SendMonitorMessageCheck.run(now, rules);
            }
            if (check == CHECK_EMAIL) {
                return SendMonitorEmailCheck.run(now, rules);
            }
            return SendMonitorFlowCheck.run(now);
        } catch (Exception error) {
            // Reported once a day per check, so a lasting failure does not flood the recipients.
            return new List<SendMonitorAlert>{ new SendMonitorAlert(TYPE_MONITOR_ERROR, check, SendMonitorConfig.day(now),
                String.format(System.Label.SM_Monitor_Error_Title, new List<Object>{ check }),
                String.format(System.Label.SM_Monitor_Error_Body, new List<Object>{ error.getMessage() })) };
        }
    }
}
