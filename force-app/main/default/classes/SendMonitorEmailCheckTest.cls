/**
 * Covers the e-mail check: audience alert from the not-sent reasons, platform alert for unknown reasons,
 * the hard bounce alert and the minimums.
 */
@IsTest
private class SendMonitorEmailCheckTest {

    @IsTest
    static void missingOptInAsksToReviewTheSegment() {
        SendMonitorTestData.setUp();
        SendMonitorSource.mocks.put('emailStatus', new List<Map<String, Object>>{
            SendMonitorTestData.emailRow('SEND_STATUS', 'NOT_SENT', 'Tried to send an email to recipient without opt-in', null, 40),
            SendMonitorTestData.emailRow('SEND_STATUS', 'SENT', null, null, 60),
            SendMonitorTestData.emailRow('SEND_STATUS', 'TEST_SENT', null, null, 2)
        });
        SendMonitorSource.mocks.put('listEmailNames', new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => '0XB000000000001AAA', 'Name' => 'October newsletter' }
        });

        List<SendMonitorAlert> alerts = SendMonitorEmailCheck.run(SendMonitorTestData.NOW, new SendMonitorRules());

        Assert.areEqual(1, alerts.size(), 'One audience alert');
        Assert.areEqual(SendMonitor.TYPE_AUDIENCE, alerts[0].type, 'Missing opt-in is an audience problem');
        Assert.isTrue(alerts[0].title.contains('October newsletter'), 'The title carries the send name');
        Assert.isTrue(alerts[0].body.contains('40') && alerts[0].body.contains('100'), 'Test sends do not count: ' + alerts[0].body);
        Assert.isTrue(alerts[0].body.contains('the contact has not opted in'), 'The explanation comes from the code list');
    }

    @IsTest
    static void unknownReasonAsksToFixTheSend() {
        SendMonitorTestData.setUp();
        SendMonitorSource.mocks.put('emailStatus', new List<Map<String, Object>>{
            SendMonitorTestData.emailRow('SEND_STATUS', 'NOT_SENT', 'Template rendering failed', null, 5)
        });

        List<SendMonitorAlert> alerts = SendMonitorEmailCheck.run(SendMonitorTestData.NOW, new SendMonitorRules());

        Assert.areEqual(1, alerts.size(), 'One content alert');
        Assert.areEqual(SendMonitor.TYPE_CONTENT, alerts[0].type, 'Unknown reason is a platform problem');
        Assert.isTrue(alerts[0].body.contains('Template rendering failed'), 'The platform reason is shown');
        Assert.isTrue(alerts[0].title.contains('0XB000000000001AAA'), 'Without a name, the title carries the Id');
    }

    @IsTest
    static void highHardBounceRateAlerts() {
        SendMonitorTestData.setUp();
        SendMonitorSource.mocks.put('emailStatus', new List<Map<String, Object>>{
            SendMonitorTestData.emailRow('SEND_STATUS', 'SENT', null, null, 200),
            SendMonitorTestData.emailRow('BOUNCE', null, 'mailbox unavailable', 'HARD', 12),
            SendMonitorTestData.emailRow('BOUNCE', null, 'mailbox full', 'SOFT', 30)
        });

        List<SendMonitorAlert> alerts = SendMonitorEmailCheck.run(SendMonitorTestData.NOW, new SendMonitorRules());

        Assert.areEqual(1, alerts.size(), 'One bounce alert');
        Assert.areEqual(SendMonitor.TYPE_BOUNCES, alerts[0].type, 'Six percent of hard bounces');
        Assert.isTrue(alerts[0].body.contains('12') && alerts[0].body.contains('6.0'), 'Soft bounces do not count: ' + alerts[0].body);
    }

    @IsTest
    static void normalSendStaysQuiet() {
        SendMonitorTestData.setUp();
        SendMonitorSource.mocks.put('emailStatus', new List<Map<String, Object>>{
            SendMonitorTestData.emailRow('SEND_STATUS', 'SENT', null, null, 1000),
            SendMonitorTestData.emailRow('SEND_STATUS', 'NOT_SENT', 'Tried to send an email to recipient without opt-in', null, 15),
            SendMonitorTestData.emailRow('BOUNCE', null, 'mailbox unavailable', 'HARD', 8),
            new Map<String, Object>{ 'send' => null, 'action' => 'SEND_STATUS', 'status' => 'SENT', 'total' => 3 }
        });

        Assert.isTrue(SendMonitorEmailCheck.run(SendMonitorTestData.NOW, new SendMonitorRules()).isEmpty(), 'Below the ratios, no alert');
        Assert.isTrue(SendMonitorEmailCheck.statusSql(SendMonitorTestData.NOW).contains('ssot__EmailEngagement__dlm'), 'Reads the e-mail engagement');
    }
}
