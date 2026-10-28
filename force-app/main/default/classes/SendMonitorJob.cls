/**
 * Schedules the send monitor every 15 minutes.
 *
 * The schedule only enqueues the check, because the Data Cloud query and the alerts run better outside
 * the scheduler context. The platform does not accept one class as both schedulable and queueable, so
 * the check is the inner class Check.
 */
public with sharing class SendMonitorJob implements Schedulable {

    public static final String JOB_NAME = 'Send Monitor';
    public static final List<Integer> MINUTES = new List<Integer>{ 0, 15, 30, 45 };

    /** @param context schedule context */
    public void execute(SchedulableContext context) {
        System.enqueueJob(new Check());
    }

    /** Check of the window that ends now. */
    public class Check implements Queueable {
        /** @param context queue context */
        public void execute(QueueableContext context) {
            SendMonitor.run(Datetime.now());
        }
    }

    /**
     * Schedules the check at minutes 0, 15, 30 and 45 of every hour. Run once, from anonymous Apex.
     *
     * @return Ids of the scheduled jobs
     */
    public static List<String> schedule() {
        return schedule(JOB_NAME);
    }

    /**
     * Job names are unique in the org, even inside tests, so tests use their own name.
     *
     * @param name prefix of the job names
     * @return Ids of the scheduled jobs
     */
    @TestVisible
    private static List<String> schedule(String name) {
        List<String> ids = new List<String>();
        for (Integer minute : MINUTES) {
            ids.add(System.schedule(name + ' :' + String.valueOf(minute).leftPad(2, '0'), '0 ' + minute + ' * * * ?', new SendMonitorJob()));
        }
        return ids;
    }
}
