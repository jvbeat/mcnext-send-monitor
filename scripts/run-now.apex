// Runs one check now and prints the alerts that were new. Useful right after installing.
for (SendMonitorAlert alert : SendMonitor.run(Datetime.now())) {
    System.debug(alert.title + '\n' + alert.body);
}
