/**
 * Covers the whole run: alerts recorded and sent once, a failing check reported without stopping the
 * others, the switches of the setting, the rules, the readers and the schedule.
 */
@IsTest
private class SendMonitorTest {

    @TestSetup
    static void addRecipient() {
        User admin = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(admin) {
            Group recipients = [SELECT Id FROM Group WHERE DeveloperName = 'Send_Monitor_Recipients' LIMIT 1];
            insert new GroupMember(GroupId = recipients.Id, UserOrGroupId = admin.Id);
        }
    }

    private static void contentProblem() {
        SendMonitorSource.mocks.put('messageStatus', new List<Map<String, Object>>{
            SendMonitorTestData.messageRow('SEND_STATUS', 'NOT_SENT', 'SF-3003', 50, null, null)
        });
    }

    @IsTest
    static void alertIsRecordedAndSentOnce() {
        SendMonitorTestData.setUp();
        contentProblem();

        Test.startTest();
        List<SendMonitorAlert> first = SendMonitor.run(SendMonitorTestData.NOW);
        List<SendMonitorAlert> second = SendMonitor.run(SendMonitorTestData.NOW.addMinutes(15));
        Integer emails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(1, first.size(), 'One alert');
        Assert.isTrue(second.isEmpty(), 'The same alert is not sent again in the day');
        Assert.areEqual(1, [SELECT COUNT() FROM Send_Monitor_Alert__c], 'The alert is recorded');
        Assert.areEqual(1, emails, 'The e-mails go in one call');
    }

    @IsTest
    static void failingCheckIsReportedAndTheOthersRun() {
        SendMonitorTestData.setUp();
        contentProblem();
        SendMonitorSource.failures.add('emailStatus');

        List<SendMonitorAlert> alerts = SendMonitor.run(SendMonitorTestData.NOW);

        Set<String> types = new Set<String>();
        for (SendMonitorAlert alert : alerts) {
            types.add(alert.type);
        }
        Assert.isTrue(types.contains(SendMonitor.TYPE_MONITOR_ERROR), 'The failing check is reported');
        Assert.isTrue(types.contains(SendMonitor.TYPE_CONTENT), 'The message check still ran');
    }

    @IsTest
    static void switchedOffChecksDoNotRun() {
        SendMonitorTestData.setUp();
        contentProblem();
        SendMonitorConfig.testSetting.Check_Messages__c = false;
        SendMonitorConfig.testSetting.Check_Email__c = false;
        SendMonitorConfig.testSetting.Check_Flows__c = false;

        Assert.isTrue(SendMonitor.run(SendMonitorTestData.NOW).isEmpty(), 'Nothing runs');
    }

    @IsTest
    static void noRecipientsStillRecords() {
        SendMonitorTestData.setUp();
        contentProblem();
        SendMonitorConfig.testSetting.Recipients_Group__c = null;

        Assert.areEqual(1, SendMonitor.run(SendMonitorTestData.NOW).size(), 'The alert is recorded even without recipients');
        Assert.areEqual(1, [SELECT COUNT() FROM Send_Monitor_Alert__c], 'Recorded');
    }

    @IsTest
    static void rulesClassifyByCodePrefixAndReason() {
        SendMonitorTestData.setUp();
        SendMonitorRules rules = new SendMonitorRules();
        Assert.areEqual(SendMonitorRules.CONTENT, rules.category('WA-132012', null), 'Meta template error is content');
        Assert.areEqual(SendMonitorRules.AUDIENCE, rules.category('WA-131047', null), 'Meta delivery error is audience');
        Assert.areEqual(SendMonitorRules.PLATFORM, rules.category(null, null), 'Nothing known is platform');
        Assert.areEqual(SendMonitorRules.AUDIENCE, rules.category(null, 'Recipient WITHOUT OPT-IN'), 'Reasons match without case');
        Assert.areEqual(SendMonitorRules.AUDIENCE, rules.category('sf-3035', null), 'Codes match without case');
    }

    @IsTest
    static void configFallsBackToDefaults() {
        SendMonitorConfig.testSetting = new Send_Monitor_Setting__mdt();
        Assert.areEqual(3, SendMonitorConfig.windowHours(), 'Window default');
        Assert.areEqual(3, SendMonitorConfig.minContentErrors(), 'Content minimum default');
        Assert.areEqual(10, SendMonitorConfig.minAudienceErrors(), 'Audience minimum default');
        Assert.areEqual(0.3, SendMonitorConfig.audienceRatio(), 'Audience ratio default');
        Assert.areEqual(0.05, SendMonitorConfig.bounceRatio(), 'Bounce ratio default');
        Assert.areEqual(0.3, SendMonitorConfig.fallbackRatio(), 'Fallback ratio default');
        Assert.areEqual(20, SendMonitorConfig.fallbackMinSends(), 'Fallback minimum default');
        Assert.areEqual(60, SendMonitorConfig.graceMinutes(), 'Grace default');
        Assert.isTrue(SendMonitorConfig.fallbackValues().isEmpty(), 'No default texts configured');
        Assert.areEqual(UserInfo.getTimeZone().getID(), SendMonitorConfig.timeZone(), 'Time zone of the user');
        Assert.areEqual('', SendMonitorConfig.dateTimeText(null), 'No date, no text');
        SendMonitorConfig.testSetting = null;
        Assert.isNotNull(SendMonitorConfig.setting(), 'The installed setting, or the defaults');
        SendMonitorConfig.testCodes = null;
        Assert.isNotNull(SendMonitorConfig.codes(), 'The installed codes');
    }

    @IsTest
    static void readersParseDataCloudAndFlattenRecords() {
        String response = JSON.serialize(new List<Object>{ new Map<String, Object>{
            'metadata' => new Map<String, Object>{
                'content' => new Map<String, Object>{ 'placeInOrder' => 0 },
                'total' => new Map<String, Object>{ 'placeInOrder' => 1 }
            },
            'data' => new List<Object>{ new List<Object>{ 'MC1', 5 } }
        } });
        List<Map<String, Object>> rows = SendMonitorSource.rows(response);
        Assert.areEqual('MC1', rows[0].get('content'), 'Column by position');
        Assert.areEqual(5, rows[0].get('total'), 'Value kept');
        Assert.isTrue(SendMonitorSource.rows(null).isEmpty(), 'No answer, no rows');

        List<Map<String, Object>> users = SendMonitorSource.soql('test',
            'SELECT Id, Profile.Name FROM User WHERE Id = :me', new Map<String, Object>{ 'me' => UserInfo.getUserId() });
        Assert.isTrue(users[0].containsKey('Profile.Name'), 'Related fields are flattened');

        Assert.isTrue(SendMonitorSource.contentNames(new Set<String>()).isEmpty(), 'No keys, no query');
        Assert.isTrue(SendMonitorSource.listEmailNames(new Set<String>()).isEmpty(), 'No Ids, no query');
        if (Type.forName(SendMonitorSource.DATA_CLOUD_CLASS) == null) {
            Assert.isTrue(SendMonitorSource.sql('noDataCloud', 'SELECT 1').isEmpty(), 'Without Data Cloud, no rows');
        }
    }

    @IsTest
    static void scheduleRunsEveryQuarterHour() {
        Test.startTest();
        List<String> ids = SendMonitorJob.schedule('Send Monitor Test');
        new SendMonitorJob().execute((SchedulableContext) null);
        Test.stopTest();
        Assert.areEqual(4, ids.size(), 'One job per quarter hour');
        Assert.areEqual(4, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Send Monitor Test%'], 'Jobs created');
    }
}
