/**
 * Covers the flow check: failed runs, runs with errors, paused flows and recurring flows that did not
 * run today, including the cases that must stay quiet.
 */
@IsTest
private class SendMonitorFlowCheckTest {

    private static final String FLOW = '2aF000000000001AAA';

    /** NOW is 15:00 in São Paulo; the usual run is at 12:00 local, 15:00 UTC. */
    private static Map<String, Object> run(Integer daysAgo, Integer hourUtc) {
        return new Map<String, Object>{
            'FlowRecordId' => FLOW,
            'FlowRecord.Name' => 'Daily journey',
            'ScheduledDate' => Datetime.newInstanceGmt(2026, 10, 28, hourUtc, 0, 0).addDays(-daysAgo)
        };
    }

    @IsTest
    static void failedRunIsReportedWithThePlatformDetail() {
        SendMonitorTestData.setUp();
        SendMonitorSource.mocks.put('failedRuns', new List<Map<String, Object>>{
            new Map<String, Object>{
                'Id' => '10p000000000001AAA', 'FlowRecordId' => FLOW, 'FlowRecord.Name' => 'Daily journey',
                'ProgressStatus' => 'Error', 'ScheduledDate' => SendMonitorTestData.NOW.addHours(-3),
                'Entries' => 0, 'Errors' => 0, 'ErrorDetail' => 'We cannot query your segment membership data.'
            },
            new Map<String, Object>{
                'Id' => '10p000000000002AAA', 'FlowRecordId' => FLOW, 'FlowRecord.Name' => 'Form follow-up',
                'ProgressStatus' => 'Completed', 'ScheduledDate' => SendMonitorTestData.NOW.addHours(-1),
                'Entries' => 4, 'Errors' => 2, 'ErrorDetail' => null
            }
        });

        List<SendMonitorAlert> alerts = SendMonitorFlowCheck.run(SendMonitorTestData.NOW);

        Assert.areEqual(2, alerts.size(), 'One alert per run');
        Assert.areEqual(SendMonitor.TYPE_FLOW_FAILED, alerts[0].type, 'Run in error');
        Assert.isTrue(alerts[0].body.contains('segment membership'), 'The platform detail is shown: ' + alerts[0].body);
        Assert.isTrue(alerts[0].body.contains('2026-10-28 12:00'), 'The run time is local');
        Assert.areEqual(SendMonitor.TYPE_FLOW_ERRORS, alerts[1].type, 'Run with errors');
        Assert.isTrue(alerts[1].body.contains('2') && alerts[1].body.contains('4'), 'Errors and entries: ' + alerts[1].body);
    }

    @IsTest
    static void pausedFlowIsReportedOncePerPause() {
        SendMonitorTestData.setUp();
        SendMonitorSource.mocks.put('pausedFlows', new List<Map<String, Object>>{
            new Map<String, Object>{
                'FlowRecordId' => FLOW, 'FlowRecord.Name' => 'Pilot', 'PausedDate' => SendMonitorTestData.NOW.addDays(-2), 'ReasonPaused' => 'Paused by admin'
            }
        });

        List<SendMonitorAlert> alerts = SendMonitorFlowCheck.run(SendMonitorTestData.NOW);

        Assert.areEqual(1, alerts.size(), 'One alert');
        Assert.areEqual(SendMonitor.TYPE_FLOW_PAUSED, alerts[0].type, 'Paused flow');
        Assert.isTrue(alerts[0].key.contains(String.valueOf(SendMonitorTestData.NOW.addDays(-2).getTime())), 'The key carries the pause moment');
        Assert.isTrue(alerts[0].body.contains('Paused by admin'), 'The reason is shown');
    }

    @IsTest
    static void dailyFlowThatDidNotRunTodayIsReported() {
        SendMonitorTestData.setUp();
        List<Map<String, Object>> runs = new List<Map<String, Object>>();
        for (Integer day = 1; day <= 7; day++) {
            runs.add(run(day, 15));
        }
        SendMonitorSource.mocks.put('recentRuns', runs);

        List<SendMonitorAlert> alerts = SendMonitorFlowCheck.run(SendMonitorTestData.NOW.addHours(2));

        Assert.areEqual(1, alerts.size(), 'One missed run');
        Assert.areEqual(SendMonitor.TYPE_FLOW_MISSED, alerts[0].type, 'Did not run today');
        Assert.isTrue(alerts[0].body.contains('12:00') && alerts[0].body.contains('7'), 'Usual time and days: ' + alerts[0].body);
    }

    @IsTest
    static void runTodayTooEarlyOrIrregularStayQuiet() {
        SendMonitorTestData.setUp();
        List<Map<String, Object>> runs = new List<Map<String, Object>>();
        for (Integer day = 0; day <= 7; day++) {
            runs.add(run(day, 15));
        }
        SendMonitorSource.mocks.put('recentRuns', runs);
        Assert.isTrue(SendMonitorFlowCheck.run(SendMonitorTestData.NOW.addHours(2)).isEmpty(), 'It ran today');

        runs.remove(0);
        Assert.isTrue(SendMonitorFlowCheck.run(SendMonitorTestData.NOW.addMinutes(-150)).isEmpty(), 'Still inside the grace time');

        SendMonitorSource.mocks.put('recentRuns', new List<Map<String, Object>>{ run(2, 15), run(4, 15), run(6, 15), run(7, 15) });
        Assert.isTrue(SendMonitorFlowCheck.run(SendMonitorTestData.NOW.addHours(2)).isEmpty(), 'Every other day is not daily');

        SendMonitorSource.mocks.put('recentRuns', new List<Map<String, Object>>{ run(1, 15), run(2, 15), run(3, 15), run(4, 15), run(5, 15), run(6, 15) });
        Assert.isTrue(SendMonitorFlowCheck.run(SendMonitorTestData.NOW.addHours(2)).isEmpty(), 'Did not run on the same weekday last week');
    }
}
