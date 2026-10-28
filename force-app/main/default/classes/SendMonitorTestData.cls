/**
 * Test setup shared by the send monitor tests: fixed settings, a small code list and empty reads, so each
 * test only declares the rows it is about.
 */
@IsTest
public class SendMonitorTestData {

    public static final Datetime NOW = Datetime.newInstanceGmt(2026, 10, 28, 18, 0, 0);
    public static final String CONTENT = 'MCTESTCONTENT00000000000000001';

    /** Fixed settings and codes, and every read answering with no rows. */
    public static void setUp() {
        Send_Monitor_Setting__mdt setting = SendMonitorConfig.defaults();
        setting.Time_Zone__c = 'America/Sao_Paulo';
        SendMonitorConfig.testSetting = setting;
        SendMonitorConfig.testCodes = new List<Send_Monitor_Code__mdt>{
            code('MESSAGE', 'SF-3003', null, 'CONTENT', 'internal error of the platform'),
            code('MESSAGE', 'SF-3035', null, 'AUDIENCE', 'the contact has no mobile phone'),
            code('WHATSAPP', 'WA-132000', null, 'CONTENT', 'the content has a different number of variables'),
            code('EMAIL', null, 'without opt-in', 'AUDIENCE', 'the contact has not opted in')
        };
        for (String name : new List<String>{
            'messageStatus', 'messageTexts', 'emailStatus', 'contentNames', 'listEmailNames', 'failedRuns', 'pausedFlows', 'recentRuns'
        }) {
            SendMonitorSource.mocks.put(name, new List<Map<String, Object>>());
        }
    }

    public static Send_Monitor_Code__mdt code(String channel, String code, String reason, String category, String explanation) {
        return new Send_Monitor_Code__mdt(
            Channel__c = channel,
            Code__c = code,
            Reason_Contains__c = reason,
            Category__c = category,
            Explanation__c = explanation
        );
    }

    /** @return one row of the message status query */
    public static Map<String, Object> messageRow(String action, String status, String code, Integer total, String message, String sample) {
        return new Map<String, Object>{
            'content' => CONTENT, 'channel' => 'WHATSAPP', 'action' => action, 'status' => status,
            'code' => code, 'total' => total, 'message' => message, 'sample' => sample
        };
    }

    /** @return one row of the e-mail status query */
    public static Map<String, Object> emailRow(String action, String status, String reason, String bounce, Integer total) {
        return new Map<String, Object>{
            'send' => '0XB000000000001AAA', 'action' => action, 'status' => status,
            'reason' => reason, 'bounce' => bounce, 'total' => total
        };
    }

    /** @return the payload of a WhatsApp message with one body parameter */
    public static Map<String, Object> textRow(String value) {
        return new Map<String, Object>{
            'content' => CONTENT,
            'text' => '{&quot;template&quot;:{&quot;components&quot;:[{&quot;type&quot;:&quot;body&quot;,&quot;parameters&quot;:[{&quot;text&quot;:&quot;'
                + value + '&quot;,&quot;type&quot;:&quot;text&quot;}]}],&quot;name&quot;:&quot;welcome&quot;}}'
        };
    }
}
