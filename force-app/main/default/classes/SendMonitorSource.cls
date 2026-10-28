/**
 * Reads the data the checks use: Data Cloud SQL through SendMonitorDataCloud, and SOQL on flow runs,
 * contents and list e-mails.
 *
 * Every read returns rows as maps, with related fields flattened as "Relationship.Field". That keeps the
 * checks independent of objects that only exist in orgs with Marketing Cloud Next and Data Cloud, and lets
 * tests replace any read by name. The Data Cloud class is loaded by name because ConnectApi.CdpQuery only
 * compiles in orgs with Data Cloud; without it, the Data Cloud reads return no rows.
 *
 * The reads run in system mode: the monitor reports on platform records that the scheduling user does
 * not need access to, and it only reads them.
 */
public with sharing class SendMonitorSource {

    public static final String DATA_CLOUD_CLASS = 'SendMonitorDataCloud';

    @TestVisible private static Map<String, List<Map<String, Object>>> mocks = new Map<String, List<Map<String, Object>>>();
    @TestVisible private static Set<String> failures = new Set<String>();

    /**
     * @param name name of the read, used by tests to replace it
     * @param query Data Cloud SQL
     * @return one map per row, with the column alias as key
     */
    public static List<Map<String, Object>> sql(String name, String query) {
        fail(name);
        if (mocks.containsKey(name)) {
            return mocks.get(name);
        }
        Type dataCloud = Type.forName(DATA_CLOUD_CLASS);
        if (dataCloud == null) {
            return new List<Map<String, Object>>();
        }
        Callable reader = (Callable) dataCloud.newInstance();
        return rows((String) reader.call('query', new Map<String, Object>{ 'sql' => query }));
    }

    /**
     * @param name name of the read, used by tests to replace it
     * @param query SOQL with binds
     * @param binds bind values by name
     * @return one map per record, with related fields as "Relationship.Field"
     */
    public static List<Map<String, Object>> soql(String name, String query, Map<String, Object> binds) {
        fail(name);
        if (mocks.containsKey(name)) {
            return mocks.get(name);
        }
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (SObject record : Database.queryWithBinds(query, binds, AccessLevel.SYSTEM_MODE)) {
            result.add(flatten(record, ''));
        }
        return result;
    }

    /**
     * @param keys content keys from the engagement data
     * @return content name by key
     */
    public static Map<String, String> contentNames(Set<String> keys) {
        Map<String, String> names = new Map<String, String>();
        if (keys.isEmpty()) {
            return names;
        }
        for (Map<String, Object> row : soql('contentNames',
            'SELECT ContentKey, Name FROM ManagedContent WHERE ContentKey IN :keys',
            new Map<String, Object>{ 'keys' => keys })) {
            names.put((String) row.get('ContentKey'), (String) row.get('Name'));
        }
        return names;
    }

    /**
     * @param ids list e-mail Ids from the engagement data
     * @return list e-mail name by Id
     */
    public static Map<String, String> listEmailNames(Set<String> ids) {
        Map<String, String> names = new Map<String, String>();
        if (ids.isEmpty()) {
            return names;
        }
        for (Map<String, Object> row : soql('listEmailNames',
            'SELECT Id, Name FROM ListEmail WHERE Id IN :ids',
            new Map<String, Object>{ 'ids' => ids })) {
            names.put(String.valueOf(row.get('Id')), (String) row.get('Name'));
        }
        return names;
    }

    /**
     * @param response JSON with the query batches, each with metadata (column and position) and data
     * @return one map per row, with the column name as key
     */
    @TestVisible
    private static List<Map<String, Object>> rows(String response) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        if (String.isBlank(response)) {
            return result;
        }
        for (Object item : (List<Object>) JSON.deserializeUntyped(response)) {
            Map<String, Object> batch = (Map<String, Object>) item;
            Map<String, Object> metadata = (Map<String, Object>) batch.get('metadata');
            Map<Integer, String> columnByPosition = new Map<Integer, String>();
            for (String column : metadata.keySet()) {
                columnByPosition.put(Integer.valueOf(((Map<String, Object>) metadata.get(column)).get('placeInOrder')), column);
            }
            for (Object data : (List<Object>) batch.get('data')) {
                List<Object> values = (List<Object>) data;
                Map<String, Object> row = new Map<String, Object>();
                for (Integer i = 0; i < values.size(); i++) {
                    row.put(columnByPosition.get(i), values[i]);
                }
                result.add(row);
            }
        }
        return result;
    }

    @TestVisible
    private static Map<String, Object> flatten(SObject record, String prefix) {
        Map<String, Object> row = new Map<String, Object>();
        Map<String, Object> fields = record.getPopulatedFieldsAsMap();
        for (String field : fields.keySet()) {
            Object value = fields.get(field);
            if (value instanceof SObject) {
                row.putAll(flatten((SObject) value, prefix + field + '.'));
            } else {
                row.put(prefix + field, value);
            }
        }
        return row;
    }

    /** Lets tests make one read fail, to cover the error alert. */
    private static void fail(String name) {
        if (failures.contains(name)) {
            throw new SendMonitorException('Read ' + name + ' failed in test');
        }
    }

    public class SendMonitorException extends Exception {}
}
