import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';
import 'package:credential_manager/credential_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SorobanService {

  static Future<String> handleDeploy({
    required String credentialsId,
    required AuthenticatorAttestationResponse attestationResponse}) async {

    final server = SorobanServer(getRpcUrl());
    server.enableLogging = true;

    final publicKey = PasskeyUtils.getPublicKey(attestationResponse);

    if (publicKey == null) {
      throw Exception("Could not extract public key from attestation response");
    }

    final contractSalt = PasskeyUtils.getContractSalt(credentialsId);
    final factoryContractId = getFactoryContractId();
    final network = getNetwork();
    final contractId = PasskeyUtils.deriveContractId(contractSalt: contractSalt,
        factoryContractId: factoryContractId, network: network);
    log("Contract id: $contractId");

    final bundlerKey = await getBundlerKey();
    final bundlerKeyAccount = await server.getAccount(bundlerKey.accountId);
    if (bundlerKeyAccount == null) {
      log("bundlerKeyAccount not found: ${bundlerKey.accountId}");
      throw ArgumentError("bundler account not funded");
    }

    final deployFunction = InvokeContractHostFunction(
        factoryContractId,
        'deploy',
        arguments: [
          XdrSCVal.forBytes(contractSalt),
          XdrSCVal.forBytes(publicKey),
        ]);

    final operation =
        InvokeHostFuncOpBuilder(deployFunction).build();

    final transaction = TransactionBuilder(bundlerKeyAccount).addOperation(operation).build();
    final request = SimulateTransactionRequest(transaction);
    final simulateResponse = await server.simulateTransaction(request);

    if (simulateResponse.resultError != null) {
      throw Exception("Could not simulate transaction");
    }

    transaction.sorobanTransactionData = simulateResponse.transactionData;
    transaction.addResourceFee(simulateResponse.minResourceFee!);
    transaction.sign(bundlerKey, network);

    final sendResponse = await server.sendTransaction(transaction);
    if (sendResponse.status == SendTransactionResponse.STATUS_ERROR) {
      log("Send transaction error: ${sendResponse.errorResultXdr}");
    }

    return contractId;
  }

  static Future<String> handleSignIn({required String credentialsId}) async {

    final server = SorobanServer(getRpcUrl());
    server.enableLogging = true;

    // signin cannot retrieve a public-key so we can only derive the
    // contract address
    final contractSalt = PasskeyUtils.getContractSalt(credentialsId);
    final factoryContractId = getFactoryContractId();
    final network = getNetwork();
    final contractId = PasskeyUtils.deriveContractId(contractSalt: contractSalt,
        factoryContractId: factoryContractId, network: network);

    final cData = await server.getContractData(contractId,
        XdrSCVal.forLedgerKeyContractInstance(),
        XdrContractDataDurability.PERSISTENT);

    if (cData == null) {
      throw Exception("contract not found: $contractId");
    }

    return contractId;
  }

  static Future<VoteBuildResult> handleVoteBuild(
      {required String accountContractId, required bool vote}) async {

    final server = SorobanServer(getRpcUrl());
    server.enableLogging = true;

    final lastLedger = (await server.getLatestLedger()).sequence!;
    final bundlerKey = await getBundlerKey();
    final bundlerKeyAccount = await server.getAccount(bundlerKey.accountId);
    if (bundlerKeyAccount == null) {
      throw ArgumentError("bundler account not funded: ${bundlerKey.accountId}");
    }
    final chickenEggContractId = getChickenEggContractId();
    final voteFunction = InvokeContractHostFunction(
        chickenEggContractId,
        'vote',
        arguments: [
          XdrSCVal.forContractAddress(accountContractId),
          XdrSCVal.forBool(vote)
        ]);

    final operation =
    InvokeHostFuncOpBuilder(voteFunction).build();

    final authTxn = TransactionBuilder(bundlerKeyAccount).addOperation(operation).build();
    final request = SimulateTransactionRequest(authTxn);
    final simulateResponse = await server.simulateTransaction(request);

    if (simulateResponse.resultError != null) {
      throw Exception("could not simulate transaction");
    }

    authTxn.sorobanTransactionData = simulateResponse.transactionData;
    authTxn.addResourceFee(simulateResponse.minResourceFee!);

    List<SorobanAuthorizationEntry>? auth = simulateResponse.sorobanAuth;
    if (auth == null || auth.isEmpty) {
      throw Exception("no soroban auth in simulation result");
    }
    authTxn.setSorobanAuth(auth);

    final addressCredentials = auth.first.credentials.addressCredentials;
    if (addressCredentials == null) {
      throw Exception("no address credentials found in simulation auth result");
    }

    final preimage = XdrHashIDPreimage(XdrEnvelopeType.ENVELOPE_TYPE_SOROBAN_AUTHORIZATION);
    XdrHashIDPreimageSorobanAuthorization preimageSa =
    XdrHashIDPreimageSorobanAuthorization(
        XdrHash(getNetwork().networkId!),
        XdrInt64(addressCredentials.nonce),
        XdrUint32(lastLedger + 100),
        auth.first.rootInvocation.toXdr());

    preimage.sorobanAuthorization = preimageSa;

    XdrDataOutputStream xdrOutputStream = XdrDataOutputStream();
    XdrHashIDPreimage.encode(xdrOutputStream, preimage);
    final authHash = Util.hash(Uint8List.fromList(xdrOutputStream.bytes));

    return VoteBuildResult(authTxn, authHash, lastLedger);
  }

  static Future<void> handleVoteSend(
      {required Transaction authTxn,
        required int lastLedger,  required PublicKeyCredential signRes }) async {

    final server = SorobanServer(getRpcUrl());
    server.enableLogging = true;

    final sigRawBase64 = signRes.response?.signature;
    if (sigRawBase64 == null) {
      throw ArgumentError("Signature not found in credentials result");
    }
    final signatureRaw = base64Url.decode(base64Url.normalize(sigRawBase64));
    final signature = PasskeyUtils.compactSignature(signatureRaw);

    if (authTxn.operations.isEmpty || authTxn.operations.first is! InvokeHostFunctionOperation) {
      throw ArgumentError("Invalid authThx (first operation is not InvokeHostFunctionOperation)");
    }

    final op = authTxn.operations.first as InvokeHostFunctionOperation;
    if (op.auth.isEmpty) {
      throw ArgumentError("Invalid authThx (op.auth is empty)");
    }

    final credentials = op.auth.first.credentials.addressCredentials;
    if (credentials == null) {
      throw ArgumentError("Invalid authThx (credentials not found)");
    }
    
    credentials.signatureExpirationLedger = lastLedger + 100;

    final authenticatorDataB64 = signRes.response?.authenticatorData;
    if (authenticatorDataB64 == null) {
      throw ArgumentError("Invalid sigRes (response.authenticatorData not found)");
    }
    final authenticatorData = base64Url.decode(base64Url.normalize(authenticatorDataB64));

    final clientDataJsonB64 = signRes.response?.clientDataJSON;
    if (clientDataJsonB64 == null) {
      throw ArgumentError("Invalid sigRes (response.clientDataJSON not found)");
    }
    final clientDataJson = base64Url.decode(base64Url.normalize(clientDataJsonB64));

    final credentialsSignature = XdrSCVal.forMap([
      XdrSCMapEntry(XdrSCVal.forSymbol('authenticator_data'), XdrSCVal.forBytes(authenticatorData)),
      XdrSCMapEntry(XdrSCVal.forSymbol('client_data_json'), XdrSCVal.forBytes(clientDataJson)),
      XdrSCMapEntry(XdrSCVal.forSymbol('signature'), XdrSCVal.forBytes(signature)),
    ]);

    credentials.signature = credentialsSignature;

    final request = SimulateTransactionRequest(authTxn);
    final simulateResponse = await server.simulateTransaction(request);

    if (simulateResponse.resultError != null) {
      if (simulateResponse.resultError!.contains('failed secp256r1 verification')) {
        throw Exception("Invalid signature");
      } else {
        throw Exception("Could not simulate transaction: ${simulateResponse.resultError!}");
      }
    }

    authTxn.sorobanTransactionData = simulateResponse.transactionData;
    authTxn.addResourceFee(simulateResponse.minResourceFee!);

    final List<SorobanAuthorizationEntry>? auth = simulateResponse.sorobanAuth;
    if (auth == null || auth.isEmpty) {
      throw Exception("No soroban auth in simulation result");
    }
    authTxn.setSorobanAuth(auth);

    final bundlerKey = await getBundlerKey();
    authTxn.sign(bundlerKey, getNetwork());

    final sendResponse = await server.sendTransaction(authTxn);
    if (sendResponse.status == SendTransactionResponse.STATUS_ERROR) {
      log("Send transaction error: ${sendResponse.errorResultXdr}");
    }
  }

  static Future<Votes> getVotes(
      {required String accountContractId}) async {

    final server = SorobanServer(getRpcUrl());
    server.enableLogging = true;
    final chickenEggContractId = getChickenEggContractId();
    final getVotesFunction = InvokeContractHostFunction(
        chickenEggContractId,
        'votes',
        arguments: [
          XdrSCVal.forContractAddress(accountContractId),
        ]);

    final operation =
    InvokeHostFuncOpBuilder(getVotesFunction).build();

    final bundlerKey = await getBundlerKey();
    final transaction = TransactionBuilder(Account(bundlerKey.accountId, BigInt.zero)).addOperation(operation).build();
    final request = SimulateTransactionRequest(transaction);
    final simulateResponse = await server.simulateTransaction(request);

    if (simulateResponse.resultError != null) {
      throw Exception("Could not simulate transaction");
    }

    final returnValue = simulateResponse.results?.firstOrNull?.resultValue;
    if (returnValue == null) {
      throw Exception("Could not get votes from result");
    }

    final vec = returnValue.vec;
    if (vec == null || vec.length != 2) {
      throw Exception("Could not decode vec votes from result");
    }
    final allVotesMap = vec[0].map;
    if (allVotesMap == null || allVotesMap.length != 2) {
      throw Exception("Could not decode all votes map from result");
    }
    final sourceVotesMap = vec[1].map;
    if (sourceVotesMap == null || sourceVotesMap.length != 2) {
      throw Exception("Could not decode source votes map from result");
    }
    int allChicken = 0;
    int allEgg = 0;
    int sourceChicken = 0;
    int sourceEgg = 0;

    for (var entry in allVotesMap) {
      if (entry.key.sym == "chicken") {
        allChicken = entry.val.u32 != null ? entry.val.u32!.uint32 : 0;
      }
      if (entry.key.sym == "egg") {
        allEgg = entry.val.u32 != null ? entry.val.u32!.uint32 : 0;
      }
    }

    for (var entry in sourceVotesMap) {
      if (entry.key.sym == "chicken") {
        sourceChicken = entry.val.u32 != null ? entry.val.u32!.uint32 : 0;
      }
      if (entry.key.sym == "egg") {
        sourceEgg = entry.val.u32 != null ? entry.val.u32!.uint32 : 0;
      }
    }

    return Votes(allChicken, allEgg, sourceChicken, sourceEgg);

  }

  static Future<KeyPair> getBundlerKey() async {
    final prefs = await SharedPreferences.getInstance();
    final bundlerSecret = dotenv.env['bundler_secret'] ?? prefs.getString('sp:bundler');
    final bundlerKey = bundlerSecret == null
        ? KeyPair.random()
        : KeyPair.fromSecretSeed(bundlerSecret);
    if (bundlerSecret == null) {
      final network = getNetwork();
      if (network.networkPassphrase == Network.TESTNET.networkPassphrase) {
        await FriendBot.fundTestAccount(bundlerKey.accountId);
      } else if (network.networkPassphrase == Network.FUTURENET.networkPassphrase) {
        await FuturenetFriendBot.fundTestAccount(bundlerKey.accountId);
      } else {
        throw Exception("Can not fund new bundler account. Fix by adding bundler_secret to .env");
      }
      prefs.setString('sp:bundler', bundlerKey.secretSeed);
    }
    return bundlerKey;
  }

  static String getRpcUrl() {
    final value = dotenv.env['rpc_url'];
    if (value == null) {
      throw Exception(".env file must contain rpc_url");
    }
    return value;
  }

  static String getFactoryContractId() {
    final value = dotenv.env['factory_contract_id'];
    if (value == null) {
      throw Exception(".env file must contain factory_contract_id");
    }
    return value;
  }

  static String getChickenEggContractId() {
    final value = dotenv.env['chicken_egg_contract_id'];
    if (value == null) {
      throw Exception(".env file must contain chicken_egg_contract_id");
    }
    return value;
  }

  static Network getNetwork() {
    final value = dotenv.env['network_passphrase'];
    if (value == null) {
      throw Exception(".env file must contain network_passphrase");
    }
    return Network(value);
  }
}

class VoteBuildResult {
  Transaction authTxn;
  Uint8List authHash;
  int lastLedger;

  VoteBuildResult(this.authTxn, this.authHash, this.lastLedger);
}

class Votes {
  int allChicken;
  int allEgg;
  int sourceChicken;
  int sourceEgg;

  Votes(this.allChicken, this.allEgg, this.sourceChicken, this.sourceEgg);
}