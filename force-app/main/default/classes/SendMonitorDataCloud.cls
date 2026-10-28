/**
 * Runs Data Cloud SQL for the send monitor.
 *
 * It lives in its own class because ConnectApi.CdpQuery only exists in orgs with Data Cloud: the monitor
 * loads this class by name and, where it does not exist, runs without the Data Cloud checks. The answer
 * goes back as JSON, so the monitor does not depend on the ConnectApi types.
 */
public with sharing class SendMonitorDataCloud implements Callable {

    /**
     * @param action only 'query' is accepted
     * @param args 'sql' with the query
     * @return JSON with the list of answer batches, each with metadata and data
     */
    public Object call(String action, Map<String, Object> args) {
        if (action != 'query') {
            throw new IllegalArgumentException('Unsupported action: ' + action);
        }
        ConnectApi.CdpQueryInput input = new ConnectApi.CdpQueryInput();
        input.sql = (String) args.get('sql');
        return JSON.serialize(batches(ConnectApi.CdpQuery.queryAnsiSqlV2(input)));
    }

    /**
     * @param first first batch of the answer
     * @return all batches, following the next batch while the platform returns one
     */
    @TestVisible
    private static List<ConnectApi.CdpQueryOutputV2> batches(ConnectApi.CdpQueryOutputV2 first) {
        List<ConnectApi.CdpQueryOutputV2> result = new List<ConnectApi.CdpQueryOutputV2>{ first };
        while (String.isNotBlank(result[result.size() - 1].nextBatchId)) {
            result.add(ConnectApi.CdpQuery.nextBatchAnsiSqlV2(result[result.size() - 1].nextBatchId));
        }
        return result;
    }
}
