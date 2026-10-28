/**
 * Reads the settings and the known error codes of the send monitor from custom metadata.
 *
 * Without a Default setting record, the monitor runs with the values in defaults(). Tests replace both
 * the setting and the code list, so they do not depend on the records installed in the org.
 */
public with sharing class SendMonitorConfig {

    public static final String SETTING_NAME = 'Default';

    @TestVisible private static Send_Monitor_Setting__mdt testSetting;
    @TestVisible private static List<Send_Monitor_Code__mdt> testCodes;
    private static Send_Monitor_Setting__mdt cached;

    /** @return the Default setting record, or the built-in defaults when it does not exist */
    public static Send_Monitor_Setting__mdt setting() {
        if (testSetting != null) {
            return testSetting;
        }
        if (cached == null) {
            cached = Send_Monitor_Setting__mdt.getInstance(SETTING_NAME);
            if (cached == null) {
                cached = defaults();
            }
        }
        return cached;
    }

    /** @return the values the monitor uses when no setting record is installed */
    public static Send_Monitor_Setting__mdt defaults() {
        return new Send_Monitor_Setting__mdt(
            Window_Hours__c = 3,
            Min_Content_Errors__c = 3,
            Min_Audience_Errors__c = 10,
            Audience_Ratio__c = 0.3,
            Bounce_Ratio__c = 0.05,
            Fallback_Ratio__c = 0.3,
            Fallback_Min_Sends__c = 20,
            Fallback_Values__c = 'customer',
            Missed_Run_Grace_Minutes__c = 60,
            Recipients_Group__c = 'Send_Monitor_Recipients',
            Subject_Prefix__c = '[Marketing Cloud]',
            Time_Zone__c = 'America/New_York',
            Check_Messages__c = true,
            Check_Email__c = true,
            Check_Flows__c = true
        );
    }

    /** @return the known error codes and not-sent reasons */
    public static List<Send_Monitor_Code__mdt> codes() {
        return testCodes != null ? testCodes : Send_Monitor_Code__mdt.getAll().values();
    }

    public static Integer windowHours() {
        return whole(setting().Window_Hours__c, 3);
    }

    public static Integer minContentErrors() {
        return whole(setting().Min_Content_Errors__c, 3);
    }

    public static Integer minAudienceErrors() {
        return whole(setting().Min_Audience_Errors__c, 10);
    }

    public static Decimal audienceRatio() {
        return decimalOr(setting().Audience_Ratio__c, 0.3);
    }

    public static Decimal bounceRatio() {
        return decimalOr(setting().Bounce_Ratio__c, 0.05);
    }

    public static Decimal fallbackRatio() {
        return decimalOr(setting().Fallback_Ratio__c, 0.3);
    }

    public static Integer fallbackMinSends() {
        return whole(setting().Fallback_Min_Sends__c, 20);
    }

    /** @return the default texts of the contents, in lower case */
    public static Set<String> fallbackValues() {
        Set<String> values = new Set<String>();
        String configured = setting().Fallback_Values__c;
        if (String.isNotBlank(configured)) {
            for (String value : configured.split(',')) {
                if (String.isNotBlank(value)) {
                    values.add(value.trim().toLowerCase());
                }
            }
        }
        return values;
    }

    public static Integer graceMinutes() {
        return whole(setting().Missed_Run_Grace_Minutes__c, 60);
    }

    public static String timeZone() {
        String zone = setting().Time_Zone__c;
        return String.isBlank(zone) ? UserInfo.getTimeZone().getID() : zone;
    }

    /**
     * @param moment instant to format
     * @return the day of the instant in the configured time zone, as yyyy-MM-dd
     */
    public static String day(Datetime moment) {
        return moment.format('yyyy-MM-dd', timeZone());
    }

    /**
     * @param moment instant to format
     * @return date and time of the instant in the configured time zone, as yyyy-MM-dd HH:mm
     */
    public static String dateTimeText(Datetime moment) {
        return moment == null ? '' : moment.format('yyyy-MM-dd HH:mm', timeZone());
    }

    private static Integer whole(Decimal value, Integer fallback) {
        return value == null ? fallback : value.intValue();
    }

    private static Decimal decimalOr(Decimal value, Decimal fallback) {
        return value == null ? fallback : value;
    }
}
