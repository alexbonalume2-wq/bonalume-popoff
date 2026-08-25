import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class GestioneBluetooth {
  // Il "motore" principale della nuova libreria
  static final flutterReactiveBle = FlutterReactiveBle();
  
  // Invece di un oggetto complesso, ci basta salvare l'ID (Mac Address) della centralina
  static String? connectedDeviceId;
  
  // Questa ci serve per mantenere viva la connessione
  static StreamSubscription<ConnectionStateUpdate>? connectionStream;

  // Convertiamo le tue stringhe in oggetti Uuid richiesti dalla libreria
  static final Uuid serviceUuid = Uuid.parse("4fa2c732-ca0a-40d6-bc3c-ebc26d7f3c4d");
  static final Uuid rxCharacteristicUuid = Uuid.parse("beb5483e-36e1-4688-b7f5-ea07361b26a8");
  static final Uuid txCharacteristicUuid = Uuid.parse("beb5483e-36e1-4688-b7f5-ea07361b26a9");

  static Future<void> sendCommand(String comando) async {
    print("➡️ ENTRATO IN sendCommand: $comando");
    if (connectedDeviceId == null) {
      print("❌ Errore: Nessun ID dispositivo connesso.");
      return;
    }

    // Creiamo il "tubo" diretto verso la centralina senza fare ricerche
    final rxCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: rxCharacteristicUuid,
      deviceId: connectedDeviceId!,
    );

    try {
      // Scriviamo brutalmente in modo diretto (withoutResponse)
      await flutterReactiveBle.writeCharacteristicWithoutResponse(
        rxCharacteristic,
        value: comando.codeUnits,
      );
      print("✅ Comando inviato con successo DIRETTAMENTE: $comando");
    } catch (e) {
      print("❌ Errore critico durante la scrittura diretta: $e");
    }
  }

  static Future<String> readData() async {
    print("➡️ ENTRATO IN readData()");
    if (connectedDeviceId == null) return "";

    final txCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: txCharacteristicUuid,
      deviceId: connectedDeviceId!,
    );

    try {
      final response = await flutterReactiveBle.readCharacteristic(txCharacteristic);
      if (response.isNotEmpty) {
        String risultato = String.fromCharCodes(response);
        print("✅ Dati letti con successo: '$risultato'");
        return risultato;
      }
    } catch (e) {
      print("❌ Errore durante la lettura: $e");
    }
    return "";
  }

  // Funzione comodissima per chiudere tutto in modo pulito
  static void disconnetti() {
    connectionStream?.cancel();
    connectedDeviceId = null;
    print("🔌 Connessione abbattuta e pulita.");
  }
}