/**
 * Turns an error code or a not-sent reason into a category and an explanation.
 *
 * Codes come from Send_Monitor_Code__mdt. A code that is not in the list is classified by its prefix: a
 * Meta template error (WA-132xxx) is a content problem, another Meta delivery error (WA-13xxxx) is an
 * audience problem, and anything else is a platform problem, explained with the platform's own message.
 */
public with sharing class SendMonitorRules {

    public static final String CONTENT = 'CONTENT';
    public static final String AUDIENCE = 'AUDIENCE';
    public static final String PLATFORM = 'PLATFORM';

    private final Map<String, Send_Monitor_Code__mdt> byCode = new Map<String, Send_Monitor_Code__mdt>();
    private final List<Send_Monitor_Code__mdt> byReason = new List<Send_Monitor_Code__mdt>();

    public SendMonitorRules() {
        for (Send_Monitor_Code__mdt code : SendMonitorConfig.codes()) {
            if (String.isNotBlank(code.Code__c)) {
                byCode.put(code.Code__c.trim().toUpperCase(), code);
            } else if (String.isNotBlank(code.Reason_Contains__c)) {
                byReason.add(code);
            }
        }
    }

    /**
     * @param code error code recorded by the platform, or null
     * @param reason not-sent reason recorded by the platform, or null
     * @return the matching record, first by code and then by reason, or null
     */
    public Send_Monitor_Code__mdt find(String code, String reason) {
        if (String.isNotBlank(code) && byCode.containsKey(code.trim().toUpperCase())) {
            return byCode.get(code.trim().toUpperCase());
        }
        if (String.isNotBlank(reason)) {
            String text = reason.toLowerCase();
            for (Send_Monitor_Code__mdt candidate : byReason) {
                if (text.contains(candidate.Reason_Contains__c.toLowerCase())) {
                    return candidate;
                }
            }
        }
        return null;
    }

    /**
     * @param code error code, or null
     * @param reason not-sent reason, or null
     * @return CONTENT, AUDIENCE or PLATFORM
     */
    public String category(String code, String reason) {
        Send_Monitor_Code__mdt known = find(code, reason);
        if (known != null && String.isNotBlank(known.Category__c)) {
            return known.Category__c.trim().toUpperCase();
        }
        if (code != null && code.startsWith('WA-132')) {
            return CONTENT;
        }
        if (code != null && code.startsWith('WA-13')) {
            return AUDIENCE;
        }
        return PLATFORM;
    }

    /**
     * @param code error code, or null
     * @param reason not-sent reason or platform message, or null
     * @return what happened and what to do, or the platform message when the code is unknown
     */
    public String explanation(String code, String reason) {
        Send_Monitor_Code__mdt known = find(code, reason);
        if (known != null && String.isNotBlank(known.Explanation__c)) {
            return known.Explanation__c;
        }
        return String.format(System.Label.SM_Platform_Said, new List<Object>{ reason == null ? '' : reason });
    }
}
