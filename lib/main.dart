import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'bluetooth_service.dart';
import 'dart:async'; // Aggiunto per gestire i Timer e gli Stream
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bonalume Tuning',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ScreenConnessione(),
    );
  }
}
// 1. SCHERMATA CONNESSIONE BLUETOOTH
class ScreenConnessione extends StatefulWidget {
  const ScreenConnessione({super.key});

  @override
  State<ScreenConnessione> createState() => _ScreenConnessioneState();
}

class _ScreenConnessioneState extends State<ScreenConnessione> {
  bool isScanning = false;
  List<DiscoveredDevice> scanResults = [];
  StreamSubscription<DiscoveredDevice>? scanSubscription;
  String statoResetPin = "";
  
  bool isItaliano = true;

  @override
  void initState() {
    super.initState();
    _caricaLingua();
  }

  Future<void> _caricaLingua() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isItaliano = prefs.getBool('is_italiano') ?? true;
    });
  }

  Future<void> _impostaLingua(bool italiano) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isItaliano = italiano;
    });
    await prefs.setBool('is_italiano', italiano);
  }

  String t(String it, String en) {
    return isItaliano ? it : en;
  }

  void avviaScansione() async {
    // 1. RICHIESTA PERMESSI IN AUTOMATICO (Fa comparire il pop-up di Android)
    var permessi = await [
      Permission.location, 
      Permission.bluetoothScan, 
      Permission.bluetoothConnect
    ].request();
    
    // Se l'utente rifiuta i permessi, fermiamo tutto e mostriamo un avviso
    if (permessi[Permission.location]!.isDenied || permessi[Permission.bluetoothScan]!.isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t("Permessi negati. Impossibile cercare dispositivi.", "Permissions denied. Cannot scan for devices.")),
      ));
      return;
    }

    // Aspettiamo mezzo secondo per far aggiornare lo stato di Android
    await Future.delayed(const Duration(milliseconds: 500));

    // 2. CONTROLLO SE IL BLUETOOTH E' PRONTO (Cattura se è spento o se manca il GPS)
    final bleStatus = GestioneBluetooth.flutterReactiveBle.status;
    if (bleStatus != BleStatus.ready) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          t("ATTENZIONE: Bluetooth o Posizione SPENTI! Accendili per continuare.", "WARNING: Bluetooth or Location OFF! Turn them on."),
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ));
      return; // Blocca la scansione a vuoto
    }

    // 3. SE I PERMESSI CI SONO E IL BT E' ACCESO, PARTE LA RICERCA NORMALE
    setState(() {
      isScanning = true;
      scanResults.clear();
    });

    try {
      scanSubscription = GestioneBluetooth.flutterReactiveBle.scanForDevices(
        withServices: [],
        scanMode: ScanMode.lowLatency,
      ).listen((device) {
        // 🔥 FILTRO MAGICO: Mostra SOLO la tua centralina 🔥
        if (device.name == "Bonalume_PopOff_V2") {
          setState(() {
            if (!scanResults.any((d) => d.id == device.id)) {
              scanResults.add(device);
            }
          });
        }
      }, onError: (e) {
        print("❌ Errore scansione: $e");
      });

      await Future.delayed(const Duration(seconds: 10));
      scanSubscription?.cancel();
    } catch (e) {
      debugPrint("❌ Errore Bluetooth: $e");
    }

    if (!mounted) return;
    setState(() {
      isScanning = false;
    });
  }

  Future<void> resetPinLocale() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pin_salvato', '0000');
    setState(() {
      statoResetPin = t("PIN resettato = 0000", "PIN reset = 0000");
    });
  }

  void _mostraDialogoPin(BuildContext context, DiscoveredDevice device) {
    TextEditingController pinController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(t('Inserisci PIN Centralina', 'Enter ECU PIN')),
          content: TextField(
            controller: pinController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: InputDecoration(hintText: t("Es: 0000", "Ex: 0000")),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                GestioneBluetooth.disconnetti();
              },
              child: Text(t('Annulla', 'Cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                String pinInserito = pinController.text;
                if (pinInserito.length == 4) {
                  GestioneBluetooth.sendCommand("AUTH:$pinInserito");
                  
                  final prefs = await SharedPreferences.getInstance();
                  
                  if (context.mounted) {
                    Navigator.pop(context);

                    if (pinInserito == "0000") {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const ScreenImpostaPin()),
                      );
                    } else {
                      await prefs.setString('pin_salvato', pinInserito);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const ScreenPannello()),
                      );
                    }
                  }
                }
              },
              child: Text(t('Sblocca', 'Unlock')),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[500],
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // LOGO
            GestureDetector(
            onTap: () async {
  // Sceglie il link in base alla lingua impostata nell'app
  final String linkScelto = t(
    'https://www.bonalume.com/', // Link in ITALIANO
    'https://www.bonalume.com/en/' // Link in INGLESE (modifica questo con il percorso esatto!)
  );
  final Uri url = Uri.parse(linkScelto);
  await launchUrl(
    url,
    mode: LaunchMode.externalApplication,
  );
},
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                color: const Color(0xFF0047AB),
                child: Image.asset(
                  'assets/images/logo_bonalume.png',
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (context, error, stackTrace) {
                    return const Text(
                      "BONALUME",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // CONTENUTO DELLA PAGINA
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // SELETTORE LINGUA
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isItaliano ? Colors.blue : Colors.white,
                              foregroundColor: isItaliano ? Colors.white : Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: () => _impostaLingua(true),
                            child: const Text('🇮🇹 IT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: !isItaliano ? Colors.blue : Colors.white,
                              foregroundColor: !isItaliano ? Colors.white : Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: () => _impostaLingua(false),
                            child: const Text('🇬🇧 EN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // TITOLO
                    Text(
                      t('Connessione Bluetooth', 'Bluetooth Connection'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),

                    // TASTO VERDE DEMO
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      ),
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const ScreenPannello()),
                        );
                      },
                      child: Text(
                        t('MODALITÀ DEMO\n(Salta Connessione)', 'DEMO MODE\n(Skip Connection)'), 
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (GestioneBluetooth.connectedDeviceId != null) ...[
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0047AB),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        ),
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (context) => const ScreenPannello()),
                          );
                        },
                        child: Text(
                          t('Centralina già connessa:\nVai al Pannello', 'ECU already connected:\nGo to Panel'), 
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // TASTO CERCA DISPOSITIVI
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      ),
                      onPressed: avviaScansione,
                      child: Text(
                        t('Cerca Dispositivi Bluetooth', 'Search Bluetooth Devices'), 
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // TASTO RESET ROSSO
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE30022),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      ),
                      onPressed: resetPinLocale,
                      child: Text(
                        t('Reset PIN / Emergenza', 'Reset PIN / Emergency'), 
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (statoResetPin.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(statoResetPin, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color.fromARGB(255, 243, 1, 1))),
                    ],
                    const SizedBox(height: 10),

                    if (isScanning) const LinearProgressIndicator(color: Colors.blue),
                    Text(
                      t('Dispositivi trovati:', 'Discovered devices:'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 6),

                    // LISTA DISPOSITIVI
                    Expanded(
                      child: ListView.builder(
                        itemCount: scanResults.length,
                        itemBuilder: (context, index) {
                          final device = scanResults[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(
                                device.name.isEmpty ? t("Dispositivo Sconosciuto", "Unknown Device") : device.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(device.id),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                                onPressed: () async {
                                  try {
                                    GestioneBluetooth.connectedDeviceId = device.id;
                                    GestioneBluetooth.connectionStream = GestioneBluetooth.flutterReactiveBle
                                        .connectToDevice(id: GestioneBluetooth.connectedDeviceId!)
                                        .listen((connectionState) {});

                                    await Future.delayed(const Duration(seconds: 1));

                                    final prefs = await SharedPreferences.getInstance();
                                    String savedPin = prefs.getString('pin_salvato') ?? "0000";

                                    if (context.mounted) {
                                      if (savedPin == "0000") {
                                        _mostraDialogoPin(context, device);
                                      } else {
                                        await GestioneBluetooth.sendCommand("AUTH:$savedPin");
                                        if (!context.mounted) return;
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(builder: (context) => const ScreenPannello()),
                                        );
                                      }
                                    }
                                  } catch (e) {
                                    debugPrint('❌ Errore: $e');
                                  }
                                },
                                child: Text(t('Connetti', 'Connect'), style: const TextStyle(color: Colors.white)),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// NUOVA SCHERMATA: IMPOSTAZIONE NUOVO PIN E PRIVACY
class ScreenImpostaPin extends StatefulWidget {
  const ScreenImpostaPin({super.key});

  @override
  State<ScreenImpostaPin> createState() => _ScreenImpostaPinState();
}

class _ScreenImpostaPinState extends State<ScreenImpostaPin> {
  final TextEditingController _pinController = TextEditingController();
  bool isItaliano = true;

  @override
  void initState() {
    super.initState();
    _caricaLingua();
  }

  Future<void> _caricaLingua() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isItaliano = prefs.getBool('is_italiano') ?? true;
    });
  }

  String t(String it, String en) {
    return isItaliano ? it : en;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[500], // Sfondo grigio intenso (500)
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. LOGO IN CIMA A TUTTA LARGHEZZA
            GestureDetector(
             onTap: () async {
  // Sceglie il link in base alla lingua impostata nell'app
  final String linkScelto = t(
    'https://www.bonalume.com/', // Link in ITALIANO
    'https://www.bonalume.com/en/' // Link in INGLESE (modifica questo con il percorso esatto!)
  );
  final Uri url = Uri.parse(linkScelto);
  await launchUrl(
    url,
    mode: LaunchMode.externalApplication,
  );
},
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                color: const Color(0xFF0047AB),
                child: Image.asset(
                  'assets/images/logo_bonalume.png',
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (context, error, stackTrace) {
                    return const Text(
                      "BONALUME",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. CONTENUTO CENTRALE DELLA PAGINA PIN
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Testo esplicativo bilingue
                    Text(
                      t(
                        'Per motivi di sicurezza e privacy, e per evitare che la centralina venga connessa da dispositivi non autorizzati, inserisci un PIN personale.',
                        'For security and privacy reasons, and to prevent unauthorized devices from connecting to your ECU, please enter a personal PIN.'
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Campo di testo per inserire il PIN
                    TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: "0000",
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Pulsante per salvare il PIN con controllo di errore
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        String nuovoPin = _pinController.text;
                        
                        // Controlliamo che siano esattamente 4 cifre
                        if (nuovoPin.length == 4) {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('pin_salvato', nuovoPin);
                          GestioneBluetooth.sendCommand("SET_PIN:$nuovoPin");

                          if (context.mounted) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => const ScreenPannello()),
                            );
                          }
                        } else {
                          // Popup di errore bilingue se le cifre non sono 4
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: Text(
                                  t("Attenzione", "Warning"),
                                  style: const TextStyle(color: Color(0xFFE30022), fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                content: Text(
                                  t(
                                    "Devi immettere esattamente 4 numeri per il PIN.",
                                    "You must enter exactly 4 numbers for the PIN."
                                  ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                                actions: [
                                  Center(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF0047AB),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: Text(
                                        t("OK", "OK"),
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        }
                      },
                      child: Text(
                        t('Salva PIN e Continua', 'Save PIN & Continue'),
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// 2. PANNELLO PRINCIPALE
class ScreenPannello extends StatefulWidget {
  const ScreenPannello({super.key});

  @override
  State<ScreenPannello> createState() => _ScreenPannelloState();
}

class _ScreenPannelloState extends State<ScreenPannello> {
  bool isAttivo = false;
  int freq = 10;
  bool isItaliano = true;

  @override
  void initState() {
    super.initState();
    _caricaLingua();
    _aggiornaDatiAutomaticamente(); // Chiama la centralina appena si apre la pagina
  }

  Future<void> _caricaLingua() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isItaliano = prefs.getBool('is_italiano') ?? true;
    });
  }
  // FUNZIONE AUTOMATICA: Sostituisce il vecchio tasto "Aggiorna"
  Future<void> _aggiornaDatiAutomaticamente() async {
    if (GestioneBluetooth.connectedDeviceId == null) return; // Evita errori se non connesso
    
    print("🔥🔥🔥 LETTURA AUTOMATICA FREQUENZA! 🔥🔥🔥");
    await GestioneBluetooth.sendCommand("X_F");
    await Future.delayed(const Duration(milliseconds: 500));
    
    String risposta = "";
    try {
      risposta = await GestioneBluetooth.readData();
    } catch (e) {
      risposta = "";
    }

    String soloNumeri = risposta.replaceAll(RegExp(r'[^0-9]'), '');

    if (mounted) {
      setState(() {
        if (soloNumeri.isNotEmpty) {
          freq = int.parse(soloNumeri);
        }
      });
    }
  }

  String t(String it, String en) {
    return isItaliano ? it : en;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[500], // Sfondo grigio intenso coordinato
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. LOGO IN CIMA A TUTTA LARGHEZZA
            GestureDetector(
              onTap: () async {
                // Sceglie il link in base alla lingua impostata nell'app
                final String linkScelto = t(
                  'https://www.bonalume.com/auto/abarth/', // Link in ITALIANO
                  'https://www.bonalume.com/en/car/abarth/' // Link in INGLESE
                );
                final Uri url = Uri.parse(linkScelto);
                await launchUrl(
                  url,
                  mode: LaunchMode.externalApplication,
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                color: const Color(0xFF0047AB), // Blu istituzionale Bonalume
                child: Image.asset(
                  'assets/images/logo_bonalume.png',
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (context, error, stackTrace) {
                    return const Text(
                      "BONALUME",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 2. CONTENUTO SCORRIBILE DEL PANNELLO
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),

                    // TITOLO PANNELLO
                    Text(
                      t('Colpi Valvola ', 'Valve Strokes'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),

                    // LABEL FREQUENZA ORA IN CIMA AL POSTO DEL BOTTONE
                    Text(
                      '${t("Frequenza colpi attuali", "Current stroke frequency")}: $freq',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFE30022)),
                    ),
                    const SizedBox(height: 16),

                    // PULSANTI - E + (Sopra lo STUTUTU)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: () {
                              setState(() {
                                if (freq > 1) freq--;
                              });
                              GestioneBluetooth.sendCommand("F-");
                            },
                            child: const Text(
                              '-', 
                              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: () {
                              setState(() {
                                if (freq < 25) freq++;
                              });
                              GestioneBluetooth.sendCommand("F+");
                            },
                            child: const Text(
                              '+', 
                              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // TASTO STUTUTU (ROSSO)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE30022), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                      ),
                      onPressed: () {
                        setState(() { isAttivo = true; });
                        GestioneBluetooth.sendCommand("SILENCE_ON");
                      },
                      child: const Text(
                        'STUTUTU', 
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 6),

                    Text(
                      isAttivo ? t("Funzione Attivata", "Function Activated") : t("Funzione Stoppata", "Function Stopped"),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 12),

                    // TASTO STOP (NERO)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black, 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                      ),
                      onPressed: () {
                        setState(() { isAttivo = false; });
                        GestioneBluetooth.sendCommand("SILENCE_OFF");
                      },
                      child: const Text(
                        'STOP', 
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // TASTO ATTUATORE (BLU DEL LOGO)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0047AB),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context, 
                          MaterialPageRoute(builder: (context) => const ScreenAttuatore()),
                        );
                      },
                      child: Text(
                        t('ATTUATORE', 'ACTUATOR'), 
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // TASTO TORNA A CONNESSIONE (ROSSO FERRARI)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE30022), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                      ),
                      onPressed: () {
                        Navigator.pushReplacement(
                          context, 
                          MaterialPageRoute(builder: (context) => const ScreenConnessione()),
                        );
                      },
                      child: Text(
                        t('Torna a Connessione', 'Back to Connection'), 
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.help_outline, size: 40, color: Colors.white),
                        onPressed: () {
                          // ORA FUNZIONA: APRE LA SCHERMATA ISTRUZIONI
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ScreenIstruzioni()),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
  // 3. SCHERMATA ATTUATORE
class ScreenAttuatore extends StatefulWidget {
  const ScreenAttuatore({super.key});

  @override
  State<ScreenAttuatore> createState() => _ScreenAttuatoreState();
}

class _ScreenAttuatoreState extends State<ScreenAttuatore> {
  int pos = 0;
  int posizioneSalvata = 0;
  bool isItaliano = true;

  @override
  void initState() {
    super.initState();
    _caricaLingua();
    _aggiornaDatiAutomaticamente(); // Lettura automatica all'avvio della pagina
  }

  Future<void> _caricaLingua() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isItaliano = prefs.getBool('is_italiano') ?? true;
    });
  }

  // NUOVA FUNZIONE: Aggiorna automaticamente la posizione
  Future<void> _aggiornaDatiAutomaticamente() async {
    if (GestioneBluetooth.connectedDeviceId == null) return;
    
    // Per ora mantengo la logica di test che avevi nel pulsante originale.
    // SE devi interrogare il bluetooth per la posizione, sostituisci questo blocco
    // con il comando corretto (es: GestioneBluetooth.sendCommand("GET_POS")).
    if (mounted) {
      setState(() {
        pos = 10; 
      });
    }
  }

  String t(String it, String en) {
    return isItaliano ? it : en;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[500], // Sfondo grigio 500 coordinato
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. LOGO IN CIMA A TUTTA LARGHEZZA
            GestureDetector(
              onTap: () async {
                // Sceglie il link in base alla lingua impostata nell'app
                final String linkScelto = t(
                  'https://www.bonalume.com/auto/abarth/', // Link in ITALIANO
                  'https://www.bonalume.com/en/car/abarth/' // Link in INGLESE
                );
                final Uri url = Uri.parse(linkScelto);
                await launchUrl(
                  url,
                  mode: LaunchMode.externalApplication,
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                color: const Color(0xFF0047AB), // Blu istituzionale Bonalume
                child: Image.asset(
                  'assets/images/logo_bonalume.png',
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (context, error, stackTrace) {
                    return const Text(
                      "BONALUME",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 2. CONTENUTO SCORRIBILE DELL'ATTUATORE
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),

                    // TITOLO PAGINA
                    Text(
                      t('Attuatore', 'Actuator'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    
                    // LABEL POSIZIONE ORA IN CIMA AL POSTO DEL BOTTONE
                    Text(
                      '${t("Posizione", "Position")}: $pos', 
                      textAlign: TextAlign.center, 
                      style: const TextStyle(fontSize: 20, color: Color(0xFFE30022), fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    
                    // RIGA TOTAL SILENT (NERO) / TOTAL NOISY (ROSSO)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black, // Nero come richiesto
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ), 
                            onPressed: () {
                              setState(() { pos = 0; });
                              GestioneBluetooth.sendCommand("MIN");
                            }, 
                            child: const Text('Total Silent', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE30022), // Rosso come richiesto
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ), 
                            onPressed: () {
                              setState(() { pos = 20; });
                              GestioneBluetooth.sendCommand("MAX");
                            }, 
                            child: const Text('Total Noisy', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // RIGA PIÙ E MENO (-) (+)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ), 
                            onPressed: () { 
                              setState(() { if (pos > 0) pos--; }); 
                              GestioneBluetooth.sendCommand("M"); 
                            }, 
                            child: const Text('-', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ), 
                            onPressed: () { 
                              setState(() { if (pos < 25) pos++; }); 
                              GestioneBluetooth.sendCommand("P"); 
                            }, 
                            child: const Text('+', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    
                    // SAVE POSITION (ROSSO)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE30022), // Rosso richiesto
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ), 
                      onPressed: () {
                        posizioneSalvata = pos;
                        GestioneBluetooth.sendCommand("SAVE_POS");
                      }, 
                      child: Text(
                        t('Salva Posizione', 'Save Position'), 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 10),
                    
                    // RECALL POSITION (NERO)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black, // Nero richiesto
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ), 
                      onPressed: () {
                        setState(() { pos = posizioneSalvata; });
                        GestioneBluetooth.sendCommand("RECALL_POS");
                      }, 
                      child: Text(
                        t('Richiama Posizione', 'Recall Position'), 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // TORNA A PANNELLO PRINCIPALE (ROSSO)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE30022), // Rosso richiesto
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ), 
                      onPressed: () {
                        Navigator.pop(context);
                      }, 
                      child: Text(
                        t('Torna a Colpi Valvola', 'Back to Valve Strokes'), 
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    Align(
                      alignment: Alignment.centerRight, 
                      child: IconButton(
                        icon: const Icon(Icons.help_outline, size: 40, color: Colors.white), 
                        onPressed: () {
                          Navigator.push(
                            context, 
                            MaterialPageRoute(builder: (context) => const ScreenIstruzioni()),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// 4. SCHERMATA ISTRUZIONI
class ScreenIstruzioni extends StatefulWidget {
  const ScreenIstruzioni({super.key});

  @override
  State<ScreenIstruzioni> createState() => _ScreenIstruzioniState();
}

class _ScreenIstruzioniState extends State<ScreenIstruzioni> {
  bool isItaliano = true;

  @override
  void initState() {
    super.initState();
    _caricaLingua();
  }

  Future<void> _caricaLingua() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isItaliano = prefs.getBool('is_italiano') ?? true;
    });
  }

  String t(String it, String en) {
    return isItaliano ? it : en;
  }

  @override
  Widget build(BuildContext context) {
    final String testoIstruzioni = t(
      // TESTO IN ITALIANO
      r"""📘 MANUALE DI CONFIGURAZIONE BLUETOOTH

Centralina Bonalume Popoff V2

La tua nuova centralina è dotata di un sistema di sicurezza Bluetooth avanzato, progettato per garantire che solo tu possa accedere ai parametri della tua vettura.

Di seguito le istruzioni per il primo avvio, l'uso quotidiano e le procedure di emergenza.

1️⃣ PRIMO COLLEGAMENTO (Setup Iniziale)

Questa operazione va eseguita solo la prima volta che utilizzi la centralina.

Accendi il quadro della vettura per dare alimentazione alla centralina.

Apri l'App sul tuo smartphone e premi il tasto per la ricerca dei dispositivi.

Seleziona la tua centralina (nome: Bonalume Popoff V2).

Alla richiesta del codice di sicurezza, digita il PIN di fabbrica: 0000.

L'App ti chiederà immediatamente di sostituire il PIN di fabbrica con un Nuovo PIN Personale (es. un codice a 4 cifre).

Digitalo e conferma.

✅ Fatto! Da questo momento la centralina ha memorizzato il tuo PIN segreto e la tua App si è legata in modo esclusivo (tramite targa hardware) alla tua specifica centralina.

2️⃣ USO QUOTIDIANO E RADUNI (Sicurezza Attiva)

Dalla seconda volta in poi, tutto avverrà in automatico. Quando aprirai l'App, questa riconoscerà istantaneamente la tua centralina senza chiederti nuovamente il PIN.

Sei a un raduno con altre auto dotate della stessa centralina?

Nessun problema. Il nostro sistema di sicurezza impedisce due cose:

La tua App filtrerà le altre auto e si collegherà solo ed esclusivamente alla tua centralina.

Nessun altro utente potrà connettersi alla tua centralina, poiché non conosce il tuo PIN Personale segreto. In caso di tentativi non autorizzati, la centralina bloccherá immediatamente la connessione dell'estraneo.

3️⃣ CAMBIO SMARTPHONE

Se acquisti un nuovo telefono o vuoi installare l'App su un secondo dispositivo, non è necessario resettare la centralina:

Scarica l'App sul nuovo smartphone.

Esegui la scansione e seleziona la tua centralina.

Quando l'App ti chiede il codice, inserisci il tuo PIN Personale che avevi scelto al primo avvio (NON inserire 0000).

L'App si collegherà regolarmente.

⚠️ PROCEDURA DI EMERGENZA (PIN Dimenticato)

Fase 1: Reset Fisico della Centralina (Hardware)

A quadro spento (centralina in modalità riposo), individua il porta fusibile blu ed inserisci il fusibile in dotazione,

Accendi il quadro dell'auto (questo sveglierà la centralina) per almeno 10 secondi,

spegnere il quadro per almeno 1 minuto e rimuovere il fusibile.

La centralina è ora formattata e il PIN è tornato a 0000.

🛑 ATTENZIONE: Il reset nel cofano da solo non basta! Ora devi formattare anche l'App sul tuo telefono, altrimenti non riuscirai a connetterti.

Fase 2: Reset dell'Applicazione (Sul telefono)

Apri l'App sul tuo smartphone. 

nella prima pagina premi il pulsante di Reset PIN. Questo cancellerà la vecchia memoria del telefono.

Ora sei pronto per ricominciare da zero: torna alla schermata principale, esegui la scansione e segui la procedura del primo collegamento inserendo il PIN 0000.""",

      // TESTO IN INGLESE
      r"""📘 BLUETOOTH CONFIGURATION MANUAL

Bonalume Popoff V2 ECU

Your new ECU features an advanced Bluetooth security system, designed to ensure that only you can access your vehicle's parameters.

Below are the instructions for initial startup, daily use, and emergency procedures.

1️⃣ FIRST CONNECTION (Initial Setup)

This operation must be performed only the first time you use the ECU.

Turn on the vehicle's ignition to power the ECU.

Open the App on your smartphone and press the button to search for devices.

Select your ECU (name: Bonalume Popoff V2).

When prompted for the security code, enter the factory PIN: 0000.

The App will immediately prompt you to replace the factory PIN with a New Personal PIN (e.g., a 4-digit code).

Enter it and confirm.

✅ Done! From this moment on, the ECU has memorized your secret PIN, and your App is exclusively bound to your specific ECU.

2️⃣ DAILY USE & MEETS (Active Security)

From the second time onwards, everything will happen automatically. When you open the App, it will instantly recognize your ECU without asking for the PIN again.

Are you at a car meet with other cars equipped with the same ECU?

No problem. Our security system prevents unauthorized access:

Your App will filter out other cars and connect exclusively to your ECU.

No one else can connect to your ECU since they do not know your secret Personal PIN. In case of unauthorized attempts, the ECU will immediately block the connection.

3️⃣ CHANGING SMARTPHONE

If you buy a new phone or install the App on a second device, you do not need to reset the ECU:

Download the App on the new smartphone.

Scan and select your ECU.

When the App asks for the code, enter the Personal PIN you chose during the first setup (DO NOT enter 0000).

The App will connect normally.

⚠️ EMERGENCY PROCEDURE (Forgotten PIN)

Phase 1: Physical ECU Reset (Hardware)

With the ignition off (control unit in sleep mode), locate the blue fuse holder and insert the provided fuse,

​turn on the car's ignition (this will wake up the control unit) for at least 10 seconds,

​turn off the ignition for at least 1 minute and remove the fuse.

​The control unit is now formatted and the PIN has been reset to 0000.

🛑 WARNING: Resetting under the hood is not enough! You must also reset the App on your phone, otherwise, you won't be able to connect.

Phase 2: Application Reset (On the phone)

Open the App on your smartphone.

On the first page, press the Reset PIN button.

This will clear the phone's old memory.

Now you are ready to start over: go back to the main screen, scan, and follow the first connection procedure using PIN 0000.""",
    );

    return Scaffold(
      backgroundColor: Colors.grey[500], // Sfondo grigio 500 coordinato
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. LOGO IN CIMA A TUTTA LARGHEZZA
            GestureDetector(
                onTap: () async {
  // Sceglie il link in base alla lingua impostata nell'app
  final String linkScelto = t(
    'https://www.bonalume.com/istruzioni/', // Link in ITALIANO
    'https://www.bonalume.com/en/instructions/' // Link in INGLESE (modifica questo con il percorso esatto!)
  );
  final Uri url = Uri.parse(linkScelto);
  await launchUrl(
    url,
    mode: LaunchMode.externalApplication,
  );
},
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                color: const Color(0xFF0047AB), // Blu istituzionale Bonalume
                child: Image.asset(
                  'assets/images/logo_bonalume.png',
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (context, error, stackTrace) {
                    return const Text(
                      "BONALUME",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 2. CORPO DELLE ISTRUZIONI SCORRIBILE
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  testoIstruzioni,
                  style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87),
                ),
              ),
            ),
            
            // 3. TASTO TORNA INDIETRO (ROSSO FERRARI UNIFORMATO)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE30022), // Rosso Ferrari coordinato
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () {
                  Navigator.pop(context);
                }, 
                child: Text(
                  t('Torna Indietro', 'Go Back'), 
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}