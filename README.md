# Soroban Flutter Passkey Demo

Flutter passkey signing demo for soroban smart wallets.

https://github.com/user-attachments/assets/965a336f-85c6-474d-81f2-8b2e9211a0aa

## Getting Started

This demo is experimental and uses the passkey branch of the [stellar flutter sdk](https://github.com/Soneso/stellar_flutter_sdk/tree/passkey).

To obtain the credentials it uses the flutter [credential manager](https://github.com/Djsmk123/flutter_credential_manager_compose) package, but any other package can be used. 
The scope of this app is to show how you can use the stellar flutter sdk in the context of soroban passkeys.

### Setup

1. Clone this repo.
2. Create and deploy your DAL file as described [here](https://passkeys-auth.com/docs/implementation/flutter/android/). You can take [this](https://soneso.com/.well-known/assetlinks.json) and replace the fingerprint before you deploy it to your own server (rp_id). 
3. In the `.env` file from the root of the project, replace the value of `rp_id` with your own.

#### Optional:
4. Build and deploy the `webauthn-factory` soroban contract located in the `contracts` folder. Update `.env` with the new contract id.
5. Build and install the `webauthn-secp256r1` contract. Initialize the `webauthn-factory` with the wasm hash of the installed webauthn-secp256r1 contract.
6. Build and deploy the `chicken-egg-v` contract. Update `.env` with the new contract id.

## Notes

The demo is only tested on android until now.




