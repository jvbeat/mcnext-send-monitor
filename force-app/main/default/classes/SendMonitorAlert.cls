/**
 * One alert of the send monitor: what went wrong, what it is about and the text sent to the recipients.
 *
 * The key joins type, source and period, so the same problem is reported once per period. Checks that
 * report a single event, such as a failed flow run, pass the event Id as source and leave the period blank.
 */
public with sharing class SendMonitorAlert {

    public String key;
    public String type;
    public String source;
    public String title;
    public String body;

    /**
     * @param type kind of problem, one of the SendMonitor type constants
     * @param source Id of what the alert is about: content key, list e-mail Id or flow Id
     * @param period day or slot that limits repetition, or blank for single events
     * @param title alert title, used as e-mail subject and notification title
     * @param body alert text
     */
    public SendMonitorAlert(String type, String source, String period, String title, String body) {
        this.type = type;
        this.source = source;
        this.key = (type + '|' + source + '|' + (period == null ? '' : period)).left(255);
        this.title = title == null ? '' : title.left(255);
        this.body = body;
    }
}
