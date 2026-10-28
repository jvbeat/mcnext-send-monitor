/**
 * Covers the WhatsApp and SMS check: content and audience alerts, the diagnosis of typed variables and
 * of the Meta variable count, the minimums that keep isolated rejections quiet and the missing-data
 * alert from the parameters that went out.
 */
@IsTest
private class SendMonitorMessageCheckTest {

    @IsTest
    static void typedVariableAsksToFixTheContent() {
        SendMonitorTestData.setUp();
        SendMonitorSource.mocks.put('messageStatus', new List<Map<String, Object>>{
            SendMonitorTestData.messageRow('SEND_STATUS', 'NOT_SENT', 'SF-3003', 250, 'internal',
                'parameters=[{text={{$individual.firstName}}, type=text}]'),
            SendMonitorTestData.messageRow('SEND_STATUS', 'SENT', null, 10, null, null)
        });
        SendMonitorSource.mocks.put('contentNames', new List<Map<String, Object>>{
            new Map<String, Object>{ 'ContentKey' => SendMonitorTestData.CONTENT, 'Name' => 'Welcome' }
        });

        List<SendMonitorAlert> alerts = SendMonitorMessageCheck.run(SendMonitorTestData.NOW, new SendMonitorRules());

        Assert.areEqual(1, alerts.size(), 'One alert');
        Assert.areEqual(SendMonitor.TYPE_CONTENT, alerts[0].type, 'Internal error asks to fix the content');
        Assert.isTrue(alerts[0].body.contains('250'), 'The alert carries the size of the problem: ' + alerts[0].body);
        Assert.isTrue(alerts[0].body.contains('260'), 'Attempts include the messages that went out');
        Assert.isTrue(alerts[0].body.contains('{{$individual.firstName}}'), 'The alert shows the text that went out in place of the variable');
        Assert.isTrue(alerts[0].title.contains('Welcome'), 'The title carries the content name');
    }

    @IsTest
    static void audienceProblemAsksToReviewTheSegment() {
        SendMonitorTestData.setUp();
        SendMonitorSource.mocks.put('messageStatus', new List<Map<String, Object>>{
            SendMonitorTestData.messageRow('SEND_STATUS', 'NOT_SENT', 'SF-3035', 30, null, null),
            SendMonitorTestData.messageRow('SEND_STATUS', 'SENT', null, 60, null, null),
            SendMonitorTestData.messageRow('DR', 'FAILED', 'WA-131049', 10, null, null)
        });

        List<SendMonitorAlert> alerts = SendMonitorMessageCheck.run(SendMonitorTestData.NOW, new SendMonitorRules());

        Assert.areEqual(1, alerts.size(), 'One audience alert');
        Assert.areEqual(SendMonitor.TYPE_AUDIENCE, alerts[0].type, 'No mobile phone is an audience problem');
        Assert.isTrue(alerts[0].body.contains('40') && alerts[0].body.contains('90'),
            'Delivery receipts add rejections but not attempts: ' + alerts[0].body);
        Assert.isTrue(alerts[0].body.contains('the contact has no mobile phone'), 'The explanation comes from the code list');
    }

    @IsTest
    static void isolatedRejectionsStayQuiet() {
        SendMonitorTestData.setUp();
        SendMonitorSource.mocks.put('messageStatus', new List<Map<String, Object>>{
            SendMonitorTestData.messageRow('SEND_STATUS', 'NOT_SENT', 'SF-3003', 2, null, null),
            SendMonitorTestData.messageRow('SEND_STATUS', 'NOT_SENT', 'SF-3035', 5, null, null),
            SendMonitorTestData.messageRow('SEND_STATUS', 'SENT', null, 100, null, null)
        });

        Assert.isTrue(SendMonitorMessageCheck.run(SendMonitorTestData.NOW, new SendMonitorRules()).isEmpty(), 'Below the minimums, no alert');
    }

    @IsTest
    static void smallSendRejectedByTemplateAlerts() {
        SendMonitorTestData.setUp();
        SendMonitorSource.mocks.put('messageStatus', new List<Map<String, Object>>{
            SendMonitorTestData.messageRow('SEND_STATUS', 'NOT_SENT', 'WA-132000', 2,
                'body: number of localizable_params (0) does not match the expected number of params (1)', null)
        });

        List<SendMonitorAlert> alerts = SendMonitorMessageCheck.run(SendMonitorTestData.NOW, new SendMonitorRules());

        Assert.areEqual(1, alerts.size(), 'Two rejections in two attempts ask for a fix, below the minimum');
        Assert.isTrue(alerts[0].body.contains('expects 1') || alerts[0].body.contains('espera 1'), 'The alert carries the Meta count: ' + alerts[0].body);
    }

    @IsTest
    static void templateWithoutVariableAsksToRemoveIt() {
        SendMonitorTestData.setUp();
        String linked = 'parameters=[{text={{fallback (get (get @root &quot;$dataGraph&quot;) &quot;FirstName&quot;) &quot;customer&quot;}}}]';
        SendMonitorSource.mocks.put('messageStatus', new List<Map<String, Object>>{
            SendMonitorTestData.messageRow('SEND_STATUS', 'NOT_SENT', 'WA-132000', 20,
                'body: number of localizable_params (1) does not match the expected number of params (0)', linked)
        });

        List<SendMonitorAlert> alerts = SendMonitorMessageCheck.run(SendMonitorTestData.NOW, new SendMonitorRules());

        Assert.areEqual(1, alerts.size(), 'One content alert');
        Assert.isTrue(alerts[0].body.contains('has none') || alerts[0].body.contains('não tem nenhuma'), 'The alert says the template has no variable');
        Assert.isFalse(alerts[0].body.contains('@root'), 'A variable linked through the field selector is not reported as typed');
    }

    @IsTest
    static void unknownCodeUsesThePlatformMessage() {
        SendMonitorTestData.setUp();
        SendMonitorSource.mocks.put('messageStatus', new List<Map<String, Object>>{
            SendMonitorTestData.messageRow('SEND_STATUS', 'NOT_SENT', 'SF-9999', 5, 'something new', null)
        });

        List<SendMonitorAlert> alerts = SendMonitorMessageCheck.run(SendMonitorTestData.NOW, new SendMonitorRules());

        Assert.areEqual(1, alerts.size(), 'A platform error asks for a fix');
        Assert.isTrue(alerts[0].body.contains('something new'), 'Without an explanation, the platform message is used');
    }

    @IsTest
    static void defaultTextInAPersonalVariableIsReported() {
        SendMonitorTestData.setUp();
        List<Map<String, Object>> texts = new List<Map<String, Object>>();
        for (Integer i = 0; i < 15; i++) {
            texts.add(SendMonitorTestData.textRow('customer'));
        }
        for (Integer i = 0; i < 15; i++) {
            texts.add(SendMonitorTestData.textRow('Person ' + i));
        }
        SendMonitorSource.mocks.put('messageTexts', texts);

        List<SendMonitorAlert> alerts = SendMonitorMessageCheck.run(SendMonitorTestData.NOW, new SendMonitorRules());

        Assert.areEqual(1, alerts.size(), 'One missing-data alert');
        Assert.areEqual(SendMonitor.TYPE_MISSING_DATA, alerts[0].type, 'Default text in half of the messages');
        Assert.isTrue(alerts[0].body.contains('customer') && alerts[0].body.contains('{{1}}'), 'The alert names the value and the variable: ' + alerts[0].body);
    }

    @IsTest
    static void variableWithFewValuesByDesignIsNotReported() {
        SendMonitorTestData.setUp();
        List<Map<String, Object>> texts = new List<Map<String, Object>>();
        for (Integer i = 0; i < 30; i++) {
            texts.add(SendMonitorTestData.textRow(Math.mod(i, 3) == 0 ? 'Manager B' : 'Manager A'));
        }
        SendMonitorSource.mocks.put('messageTexts', texts);

        Assert.isTrue(SendMonitorMessageCheck.run(SendMonitorTestData.NOW, new SendMonitorRules()).isEmpty(),
            'Repeated values on both sides are a field with few values, not a default text');
    }

    @IsTest
    static void fixedTextAndSmallSendsAreNotReported() {
        SendMonitorTestData.setUp();
        List<Map<String, Object>> texts = new List<Map<String, Object>>();
        for (Integer i = 0; i < 30; i++) {
            texts.add(SendMonitorTestData.textRow('same for all'));
        }
        SendMonitorSource.mocks.put('messageTexts', texts);
        Assert.isTrue(SendMonitorMessageCheck.run(SendMonitorTestData.NOW, new SendMonitorRules()).isEmpty(), 'Same value for everyone is a fixed text');

        SendMonitorSource.mocks.put('messageTexts', new List<Map<String, Object>>{ SendMonitorTestData.textRow('customer') });
        Assert.isTrue(SendMonitorMessageCheck.run(SendMonitorTestData.NOW, new SendMonitorRules()).isEmpty(), 'Below the minimum of messages, no check');
    }

    @IsTest
    static void configuredDefaultTextInEveryMessageIsReported() {
        SendMonitorTestData.setUp();
        List<Map<String, Object>> texts = new List<Map<String, Object>>();
        for (Integer i = 0; i < 25; i++) {
            texts.add(SendMonitorTestData.textRow('Customer'));
        }
        SendMonitorSource.mocks.put('messageTexts', texts);

        List<SendMonitorAlert> alerts = SendMonitorMessageCheck.run(SendMonitorTestData.NOW, new SendMonitorRules());

        Assert.areEqual(1, alerts.size(), 'A configured default text in every message means the field is empty for everyone');
        Assert.isTrue(alerts[0].body.contains('25'), 'The alert counts the messages: ' + alerts[0].body);
    }

    @IsTest
    static void queriesAreWrittenInUtc() {
        Assert.isTrue(SendMonitorMessageCheck.statusSql(SendMonitorTestData.NOW).contains('TIMESTAMP \'2026-10-28 18:00:00\''), 'Window in UTC');
        Assert.isTrue(SendMonitorMessageCheck.textSql(SendMonitorTestData.NOW).contains('LIMIT 10000'), 'The payload read is limited');
        Assert.areEqual('', SendMonitorMessageCheck.typedVariable(null), 'No sample, no diagnosis');
        Assert.areEqual('', SendMonitorMessageCheck.metaCount('other message'), 'Other message, no count');
        Assert.areEqual(System.Label.SM_Channel_SMS, SendMonitorMessageCheck.channelLabel('SMS'), 'SMS keeps its name');
    }
}
