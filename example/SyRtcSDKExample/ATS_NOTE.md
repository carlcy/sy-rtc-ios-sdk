# ATS note (sample)

Demo `Info.plist` currently sets `NSAllowsArbitraryLoads=true` for local/IP HTTP convenience.

For production IP HTTPS self-signed, prefer the exception-domain snippet in
`docs/integration/samples/ios/ATS-Info.plist.snippet.xml` and install
`sy-rtc-server-ca.crt` (from `/downloads/`) into the device/simulator trust store.

When domain + public CA works, remove ATS exceptions and use system trust only.
