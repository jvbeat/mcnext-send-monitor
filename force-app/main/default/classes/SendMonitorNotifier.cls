/**
 * Records and sends the alerts of the send monitor.
 *
 * Each alert becomes a Send_Monitor_Alert__c record with a unique key, so an alert already recorded is
 * not sent again. New alerts go by e-mail and by bell notification to the active users of the recipients
 * group; the notification opens the alert record.
 */
public with sharing class SendMonitorNotifier {

    public static final String NOTIFICATION_TYPE = 'Send_Monitor_Alert';

    /**
     * @param alerts alerts found by the checks
     * @return the alerts that were new and were sent
     */
    public static List<SendMonitorAlert> send(List<SendMonitorAlert> alerts) {
        List<SendMonitorAlert> fresh = withoutRepeats(alerts);
        if (fresh.isEmpty()) {
            return fresh;
        }
        List<Send_Monitor_Alert__c> records = new List<Send_Monitor_Alert__c>();
        for (SendMonitorAlert alert : fresh) {
            records.add(new Send_Monitor_Alert__c(
                Key__c = alert.key,
                Type__c = alert.type,
                Source__c = alert.source == null ? null : alert.source.left(255),
                Title__c = alert.title,
                Body__c = alert.body == null ? null : alert.body.left(32768)
            ));
        }
        Database.SaveResult[] results = Database.insert(records, false, AccessLevel.SYSTEM_MODE);
        List<SendMonitorAlert> recorded = new List<SendMonitorAlert>();
        List<Send_Monitor_Alert__c> recordedRecords = new List<Send_Monitor_Alert__c>();
        for (Integer i = 0; i < results.size(); i++) {
            // A failed insert is a key recorded by a parallel run, which already sent the alert.
            if (results[i].isSuccess()) {
                recorded.add(fresh[i]);
                recordedRecords.add(records[i]);
            }
        }
        Set<String> recipients = recipients();
        if (!recorded.isEmpty() && !recipients.isEmpty()) {
            email(recorded, recipients);
            notify(recorded, recordedRecords, recipients);
        }
        return recorded;
    }

    private static List<SendMonitorAlert> withoutRepeats(List<SendMonitorAlert> alerts) {
        Map<String, SendMonitorAlert> byKey = new Map<String, SendMonitorAlert>();
        for (SendMonitorAlert alert : alerts) {
            byKey.put(alert.key, alert);
        }
        for (Send_Monitor_Alert__c existing : [
            SELECT Key__c FROM Send_Monitor_Alert__c WHERE Key__c IN :byKey.keySet() WITH SYSTEM_MODE
        ]) {
            byKey.remove(existing.Key__c);
        }
        return byKey.values();
    }

    private static Set<String> recipients() {
        String groupName = SendMonitorConfig.setting().Recipients_Group__c;
        if (String.isBlank(groupName)) {
            return new Set<String>();
        }
        Set<Id> members = new Set<Id>();
        for (GroupMember member : [
            SELECT UserOrGroupId FROM GroupMember WHERE Group.DeveloperName = :groupName WITH SYSTEM_MODE
        ]) {
            members.add(member.UserOrGroupId);
        }
        Set<String> active = new Set<String>();
        for (User activeUser : [SELECT Id FROM User WHERE Id IN :members AND IsActive = true WITH SYSTEM_MODE]) {
            active.add(activeUser.Id);
        }
        return active;
    }

    private static void email(List<SendMonitorAlert> alerts, Set<String> recipients) {
        Send_Monitor_Setting__mdt setting = SendMonitorConfig.setting();
        Id sender;
        if (String.isNotBlank(setting.Sender_Address__c)) {
            for (OrgWideEmailAddress address : [
                SELECT Id FROM OrgWideEmailAddress WHERE Address = :setting.Sender_Address__c WITH SYSTEM_MODE LIMIT 1
            ]) {
                sender = address.Id;
            }
        }
        String prefix = String.isBlank(setting.Subject_Prefix__c) ? '' : setting.Subject_Prefix__c + ' ';
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (SendMonitorAlert alert : alerts) {
            for (String recipient : recipients) {
                Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
                message.setTargetObjectId(recipient);
                message.setSaveAsActivity(false);
                message.setSubject(prefix + alert.title);
                message.setPlainTextBody(alert.body);
                if (sender != null) {
                    message.setOrgWideEmailAddressId(sender);
                }
                emails.add(message);
            }
        }
        try {
            Messaging.sendEmail(emails, false);
        } catch (EmailException error) {
            // Without e-mail deliverability, the alert still goes by bell and stays recorded.
            System.debug(LoggingLevel.WARN, error.getMessage());
        }
    }

    private static void notify(List<SendMonitorAlert> alerts, List<Send_Monitor_Alert__c> records, Set<String> recipients) {
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIFICATION_TYPE WITH SYSTEM_MODE LIMIT 1
        ];
        if (types.isEmpty()) {
            return;
        }
        for (Integer i = 0; i < alerts.size(); i++) {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(types[0].Id);
            notification.setTitle(alerts[i].title.left(250));
            notification.setBody(alerts[i].body == null ? '' : alerts[i].body.left(750));
            notification.setTargetId(records[i].Id);
            notification.send(recipients);
        }
    }
}
