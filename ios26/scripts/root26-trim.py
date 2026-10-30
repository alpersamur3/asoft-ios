#!/usr/bin/env python3
"""vphone-cli's trimmed service profile for iOS 26.6.2, as launchd overrides: 120 jobs a research VM
has no use for (Siri and intelligence, Find My, Wallet/NFC, Watch, Home, Maps background, iCloud and
iMessage sync, ads, telemetry, accessory updates, OTA), from Lakr233/vphone-cli
(MIT; VPhoneDaemon/Daemon/GuestServiceProfile.swift base26 and signin_followup, measured there on
the same build, Research/Guest/service_trimming.md), less weatherd (the Weather app) and the jobs
root26-churn.py already removes. Run as root on the mounted root, after root26-churn.py:

  root26-do.sh DISK.qcow2 'python3 SCRIPTS/root26-trim.py $R on|off'

on marks each label disabled in launchd's override database
(/private/var/db/com.apple.xpc.launchd/disabled.plist, what launchctl disable writes): launchd does
not load it at the next boot. launchd.plist is not touched. off removes these labels again.
Measured here (notes: IOS26-BOOT-SERVICES 10): guest CPU over the first 30 min after a start
1904 -> 1845 s, idle a minute sooner; Find My, Home, Settings and Control Center still open.
Never put CommCenter, cloudd, mobileassetd, sleepd, siriactionsd, nanoregistryd or geod here.
"""
import os, plistlib, sys

LABELS = [
    'com.apple.CallHistorySyncHelper',
    'com.apple.Maps.mapspushd',
    'com.apple.Maps.mapssyncd',
    'com.apple.OTACrashCopier',
    'com.apple.OTATaskingAgent',
    'com.apple.PerfPowerServicesExtended',
    'com.apple.PowerUIAgent',
    'com.apple.SafariBookmarksSyncAgent',
    'com.apple.SensorKitALSHelper',
    'com.apple.SiriTTSTrainingAgent',
    'com.apple.StatusKitAgent',
    'com.apple.ThreadCommissionerService',
    'com.apple.WirelessRadioManager',
    'com.apple.absd',
    'com.apple.accessibility.heard',
    'com.apple.accessoryupdaterd',
    'com.apple.adid',
    'com.apple.analyticsagent',
    'com.apple.analyticsd',
    'com.apple.ap.adprivacyd',
    'com.apple.ap.promotedcontentd',
    'com.apple.appleidsetupd',
    'com.apple.appstorecomponentsd',
    'com.apple.askpermissiond',
    'com.apple.assistant_service',
    'com.apple.audioanalyticsd',
    'com.apple.batteryintelligenced',
    'com.apple.bookassetd',
    'com.apple.callintelligenced',
    'com.apple.carkitd',
    'com.apple.cdpd',
    'com.apple.cmfsyncagent',
    'com.apple.coreidvd',
    'com.apple.corespeechd',
    'com.apple.diagnosticextensionsd',
    'com.apple.diagnosticspushd',
    'com.apple.ecosystemanalyticsd',
    'com.apple.email.maild',
    'com.apple.eyereliefd',
    'com.apple.familycircled',
    'com.apple.findmy.findmybeaconingd',
    'com.apple.findmy.findmylocated',
    'com.apple.finhealthd',
    'com.apple.fitnesscoachingd',
    'com.apple.fitnessintelligenced',
    'com.apple.followupd',
    'com.apple.gamed',
    'com.apple.generativeexperiencesd',
    'com.apple.geoanalyticsd',
    'com.apple.hangtelemetryd',
    'com.apple.homed',
    'com.apple.homeeventsd',
    'com.apple.icloud.findmydeviced',
    'com.apple.icloud.fmflocatord',
    'com.apple.icloud.searchpartyd',
    'com.apple.icloudmailagent',
    'com.apple.identityservicesd',
    'com.apple.imagent',
    'com.apple.imcore.imtransferagent',
    'com.apple.ind',
    'com.apple.inputanalyticsd',
    'com.apple.intelligencecontextd',
    'com.apple.intelligenceflowd',
    'com.apple.intelligenceplatformd',
    'com.apple.intelligencetasksd',
    'com.apple.itunescloudd',
    'com.apple.knowledgeconstructiond',
    'com.apple.maps.destinationd',
    'com.apple.mediaanalysisd.service',
    'com.apple.milod',
    'com.apple.mobile.softwareupdated',
    'com.apple.modelmanagerd',
    'com.apple.nanobackupd',
    'com.apple.nanoprefsyncd.2',
    'com.apple.nanotimekitcompaniond',
    'com.apple.navd',
    'com.apple.ndoagent',
    'com.apple.nearbyd',
    'com.apple.nfcd',
    'com.apple.ospredictiond',
    'com.apple.parsec-fbf',
    'com.apple.peopled',
    'com.apple.perfpowermetricd',
    'com.apple.photosface',
    'com.apple.powerexperienced',
    'com.apple.remindd',
    'com.apple.replicatord',
    'com.apple.routined',
    'com.apple.rtcreportingd',
    'com.apple.seld',
    'com.apple.sensorkitd',
    'com.apple.servicesintelligenced',
    'com.apple.seserviced',
    'com.apple.siri.sirireaderd',
    'com.apple.siriinferenced',
    'com.apple.siriknowledged',
    'com.apple.sociallayerd',
    'com.apple.softposreaderd',
    'com.apple.softwareupdateservicesd',
    'com.apple.spotlightknowledged',
    'com.apple.spotlightknowledged.updater',
    'com.apple.symptomsd-diag',
    'com.apple.syncdefaultsd',
    'com.apple.systemvoiceassistant',
    'com.apple.terminusd',
    'com.apple.textunderstandingd',
    'com.apple.tipsd',
    'com.apple.uarpassetmanagerd',
    'com.apple.uarpd',
    'com.apple.uarphidd',
    'com.apple.uarppersonalizationd',
    'com.apple.usbctelemetryd',
    'com.apple.videosubscriptionsd',
    'com.apple.visioncompaniond',
    'com.apple.voicebankingd',
    'com.apple.voicemail.vmd',
    'com.apple.watchlistd',
    'com.apple.watchpresenced',
    'com.apple.wifianalyticsd',
    'com.apple.wirelessinsightsd',
]


def main():
    if len(sys.argv) != 3 or sys.argv[2] not in ('on', 'off'):
        sys.exit(__doc__)
    d = os.path.join(sys.argv[1], 'private/var/db/com.apple.xpc.launchd')
    path = os.path.join(d, 'disabled.plist')
    os.makedirs(d, exist_ok=True)
    data = {}
    if os.path.exists(path):
        with open(path, 'rb') as f:
            data = plistlib.load(f)
    for label in LABELS:
        if sys.argv[2] == 'on':
            data[label] = True
        else:
            data.pop(label, None)
    with open(path, 'wb') as f:
        plistlib.dump(data, f, fmt=plistlib.FMT_BINARY)
    os.chown(path, 0, 0)
    os.chmod(path, 0o644)
    print('%s: %d labels, %d entries in disabled.plist' % (sys.argv[2], len(LABELS), len(data)))


if __name__ == '__main__':
    main()
