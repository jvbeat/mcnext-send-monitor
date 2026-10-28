/**
 * Checks the runs of Marketing Cloud Next flows through FlowRecordVersionOccurrence and FlowRecordVersion.
 *
 * It reports four problems: a run that failed, such as a segment that could not be read, which sends
 * nothing; a run where people hit an error inside the flow; a paused flow; and a recurring flow that did
 * not run today. A flow counts as recurring at a time slot when it ran around that time on at least five
 * of the last seven days, including the same weekday last week, so weekday-only flows do not alert on
 * weekends and flows that run every other day are not treated as daily.
 */
public with sharing class SendMonitorFlowCheck {

    private static final Integer SLOT_MINUTES = 15;
    private static final Integer MIN_DAYS = 5;

    /**
     * @param now moment of the check
     * @return alerts, without checking repetition
     */
    public static List<SendMonitorAlert> run(Datetime now) {
        List<SendMonitorAlert> alerts = new List<SendMonitorAlert>();
        alerts.addAll(failedRuns(now.addHours(-SendMonitorConfig.windowHours())));
        alerts.addAll(pausedFlows());
        alerts.addAll(missedRuns(now));
        return alerts;
    }

    @TestVisible
    private static List<SendMonitorAlert> failedRuns(Datetime since) {
        List<SendMonitorAlert> alerts = new List<SendMonitorAlert>();
        for (Map<String, Object> run : SendMonitorSource.soql('failedRuns',
            'SELECT Id, FlowRecordId, FlowRecord.Name, ProgressStatus, ScheduledDate, Entries, Errors, ErrorDetail '
                + 'FROM FlowRecordVersionOccurrence WHERE LastModifiedDate >= :since AND (ProgressStatus = \'Error\' OR Errors > 0)',
            new Map<String, Object>{ 'since' => since })) {
            String flow = (String) run.get('FlowRecord.Name');
            String runId = String.valueOf(run.get('Id'));
            String moment = SendMonitorConfig.dateTimeText((Datetime) run.get('ScheduledDate'));
            if ((String) run.get('ProgressStatus') == 'Error') {
                String body = String.format(System.Label.SM_Flow_Failed_Body, new List<Object>{ flow, moment });
                String detail = (String) run.get('ErrorDetail');
                if (String.isNotBlank(detail)) {
                    body += '\n\n' + String.format(System.Label.SM_Platform_Detail, new List<Object>{ detail });
                }
                alerts.add(new SendMonitorAlert(SendMonitor.TYPE_FLOW_FAILED, runId, null,
                    String.format(System.Label.SM_Flow_Failed_Title, new List<Object>{ flow }), body));
            } else {
                alerts.add(new SendMonitorAlert(SendMonitor.TYPE_FLOW_ERRORS, runId, null,
                    String.format(System.Label.SM_Flow_Errors_Title, new List<Object>{ flow }),
                    String.format(System.Label.SM_Flow_Errors_Body, new List<Object>{
                        whole(run.get('Errors')), whole(run.get('Entries')), flow, moment
                    })));
            }
        }
        return alerts;
    }

    @TestVisible
    private static List<SendMonitorAlert> pausedFlows() {
        List<SendMonitorAlert> alerts = new List<SendMonitorAlert>();
        for (Map<String, Object> version : SendMonitorSource.soql('pausedFlows',
            'SELECT FlowRecordId, FlowRecord.Name, PausedDate, ReasonPaused FROM FlowRecordVersion '
                + 'WHERE IsPaused = true AND Status = \'Active\'',
            new Map<String, Object>())) {
            String flow = (String) version.get('FlowRecord.Name');
            Datetime paused = (Datetime) version.get('PausedDate');
            String body = String.format(System.Label.SM_Flow_Paused_Body, new List<Object>{ flow, SendMonitorConfig.dateTimeText(paused) });
            String reason = (String) version.get('ReasonPaused');
            if (String.isNotBlank(reason)) {
                body += '\n\n' + String.format(System.Label.SM_Platform_Detail, new List<Object>{ reason });
            }
            alerts.add(new SendMonitorAlert(SendMonitor.TYPE_FLOW_PAUSED, String.valueOf(version.get('FlowRecordId')),
                paused == null ? null : String.valueOf(paused.getTime()),
                String.format(System.Label.SM_Flow_Paused_Title, new List<Object>{ flow }), body));
        }
        return alerts;
    }

    @TestVisible
    private static List<SendMonitorAlert> missedRuns(Datetime now) {
        String zone = SendMonitorConfig.timeZone();
        String today = now.format('yyyy-MM-dd', zone);
        String sameDayLastWeek = now.addDays(-7).format('yyyy-MM-dd', zone);
        Integer nowMinute = minuteOfDay(now, zone);
        Integer grace = SendMonitorConfig.graceMinutes();

        Map<String, String> names = new Map<String, String>();
        Map<String, Map<Integer, Set<String>>> daysBySlot = new Map<String, Map<Integer, Set<String>>>();
        Map<String, List<Integer>> minutesToday = new Map<String, List<Integer>>();
        for (Map<String, Object> run : SendMonitorSource.soql('recentRuns',
            'SELECT FlowRecordId, FlowRecord.Name, ScheduledDate FROM FlowRecordVersionOccurrence '
                + 'WHERE ScheduledDate >= :since AND FlowRecord.ProgressStatus = \'InProgress\' AND FlowRecord.IsPaused = false '
                + 'AND FlowRecord.Type IN (\'Segment\', \'Scheduled\')',
            new Map<String, Object>{ 'since' => now.addDays(-8) })) {
            Datetime scheduled = (Datetime) run.get('ScheduledDate');
            if (scheduled == null) {
                continue;
            }
            String flow = String.valueOf(run.get('FlowRecordId'));
            names.put(flow, (String) run.get('FlowRecord.Name'));
            String day = scheduled.format('yyyy-MM-dd', zone);
            Integer minute = minuteOfDay(scheduled, zone);
            if (day == today) {
                if (!minutesToday.containsKey(flow)) {
                    minutesToday.put(flow, new List<Integer>());
                }
                minutesToday.get(flow).add(minute);
                continue;
            }
            if (day < sameDayLastWeek) {
                continue;
            }
            Integer slot = (Decimal.valueOf(minute) / SLOT_MINUTES).round(System.RoundingMode.HALF_UP).intValue() * SLOT_MINUTES;
            if (!daysBySlot.containsKey(flow)) {
                daysBySlot.put(flow, new Map<Integer, Set<String>>());
            }
            if (!daysBySlot.get(flow).containsKey(slot)) {
                daysBySlot.get(flow).put(slot, new Set<String>());
            }
            daysBySlot.get(flow).get(slot).add(day);
        }

        List<SendMonitorAlert> alerts = new List<SendMonitorAlert>();
        for (String flow : daysBySlot.keySet()) {
            for (Integer slot : daysBySlot.get(flow).keySet()) {
                Set<String> days = daysBySlot.get(flow).get(slot);
                if (days.size() < MIN_DAYS || !days.contains(sameDayLastWeek) || nowMinute < slot + grace) {
                    continue;
                }
                if (ranNear(minutesToday.get(flow), slot, grace)) {
                    continue;
                }
                String slotTime = String.valueOf(slot / 60).leftPad(2, '0') + ':' + String.valueOf(Math.mod(slot, 60)).leftPad(2, '0');
                alerts.add(new SendMonitorAlert(SendMonitor.TYPE_FLOW_MISSED, flow, today + ' ' + slotTime,
                    String.format(System.Label.SM_Flow_Missed_Title, new List<Object>{ names.get(flow) }),
                    String.format(System.Label.SM_Flow_Missed_Body, new List<Object>{ names.get(flow), slotTime, days.size() })));
            }
        }
        return alerts;
    }

    private static Boolean ranNear(List<Integer> minutes, Integer slot, Integer grace) {
        if (minutes == null) {
            return false;
        }
        for (Integer minute : minutes) {
            if (minute >= slot - grace && minute <= slot + grace) {
                return true;
            }
        }
        return false;
    }

    private static Integer minuteOfDay(Datetime moment, String zone) {
        return Integer.valueOf(moment.format('H', zone)) * 60 + Integer.valueOf(moment.format('m', zone));
    }

    private static Integer whole(Object value) {
        return value == null ? 0 : Integer.valueOf(String.valueOf(value));
    }
}
