# HashLink Debugger for MacOS

For general installation instructions see [README](README.md). **Note**: The debugger requires you to have newer version of Hashlink installed. 
   * To verify compatibility type: ```hl --version``` and verify it returns a version **greater 1.11.0.**

## Codesign
Due to MacOS's security model Hashlink must be codesigned in order to be used with the debugger. This can be achieved by creating a self-signed certificate and signing the `hl` executable with it.

### Creating a certificate

1. Launch the **Keychain Access.app** _(from /Applications/Utilities)_
2. In Keychain Access select the **login** keychain in the "Keychains" list in the upper left hand corner of the window.
3. Select the following menu item (top bar):
    * Keychain Access –> Certificate Assistant –> **Create a Certificate**...
4. Set these settings:
    * **Name**: `hl-cert`
    * **Identity Type**: Self Signed Root
    * **Certificate Type**: Code Signing
5. The click **Create** (and confirm alert)
6. Click on **My Certificates**
7. Double click on your new `hl-cert` certificate.
8. Drop down the **Trust** disclosure triangle and scroll to the "Code Signing" pulldown menu and select **Always Trust** and authenticate as needed using your username and password.
9. Drag the new `hl-cert` code signing certificate (not the public or private keys of the same name) from the **login** keychain to the **System** keychain in the Keychains pane on the left hand side of the main Keychain Access window.<br/>This will move this certificate to the **System** keychain. You'll have to authorize a few more times, set it to be "Always trusted" when asked.
11. In the Keychain Access app, click and drag **hl-cert** from the **System** keychain onto the desktop.
The drag will create a ``~/Desktop/hl-cert.cer`` file used in the next step.
12. Switch to Terminal, and run the following:
    > ```sudo security add-trust -d -r trustRoot -p basic -p codeSign -k /Library/Keychains/System.keychain ~/Desktop/hl-cert.cer```
13. Delete the ``hl-cert.cer`` file from your Desktop
14. Quit Keychain Access
15. Reboot

### Signing Hashlink

Now that you created a self-signed certificate you need to sign the `hl` application with it. `cd` into the `hashlink-debugger` folder.
   * For convinience you can either run ```make codesign``` from the terminal and then enter the name of the certificate (e.g. `hl-cert`). 
   * _**OR**_ you can manually run:
> ```codesign --entitlements ./entitlements.xml -fs hl-cert $(which hl)```

You should now be able to run the debugger from VSCode.
