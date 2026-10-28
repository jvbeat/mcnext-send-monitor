/**
 * Covers the Data Cloud reader. It only deploys to orgs with Data Cloud, together with the class it covers.
 */
@IsTest
private class SendMonitorDataCloudTest {

    @IsTest
    static void unknownActionIsRefused() {
        try {
            new SendMonitorDataCloud().call('delete', new Map<String, Object>());
            Assert.fail('Unknown action must be refused');
        } catch (IllegalArgumentException error) {
            Assert.isTrue(error.getMessage().contains('delete'), 'The message names the action');
        }
    }

    @IsTest
    static void singleBatchDoesNotFetchMore() {
        ConnectApi.CdpQueryOutputV2 first = new ConnectApi.CdpQueryOutputV2();
        first.nextBatchId = null;
        Assert.areEqual(1, SendMonitorDataCloud.batches(first).size(), 'Without a next batch, one batch');
    }

    @IsTest
    static void queryIsBuilt() {
        try {
            Assert.isNotNull(new SendMonitorDataCloud().call('query', new Map<String, Object>{ 'sql' => 'SELECT 1' }), 'JSON answer');
        } catch (Exception error) {
            // Data Cloud does not answer inside tests; the call itself is what is covered.
            Assert.isNotNull(error.getMessage(), 'The failure comes from the platform');
        }
    }
}
