# Assistant en el emulador x86 de Windows

El motor de Android no funciona en un emulador x86_64. En builds debug con
`--dart-define=SW9_EMULATOR_ASSIST=true`, la app usa el mismo modelo
ejecutado con LiteRT-LM JVM en la CPU del ordenador
(`scripts/assistant-host`), accesible por `adb reverse tcp:8787 tcp:8787`.
El servicio escucha solo en localhost. Los builds release usan siempre el
modelo en el dispositivo.

Desde la raíz del repositorio:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-android-assistant.ps1
```

- `-ModelFile C:\ruta\modelo.litertlm` importa el modelo desde otra carpeta;
  debe tener el SHA-256 de `assets/models/model.json`.
- `-SkipBuild` reutiliza el APK existente y no incorpora código nuevo.
- `-Avd` elige otro emulador; por defecto crea y usa `FluffyChat_Light`
  (Android 11 AOSP x86_64, 2 GB).

`http://127.0.0.1:8787/health` debe devolver `ready: true` y el `id` y
`sha256` de `assets/models/model.json`. La app rechaza un servicio con otro
modelo.

Limitación: el servicio solo recibe el último mensaje del usuario, así que las
preguntas de aclaración de varios turnos no se pueden probar aquí.
