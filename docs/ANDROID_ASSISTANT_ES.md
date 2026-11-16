# Assistant v2 en Windows

Rama: `simple_interface`. Integracion preparada tras hacer pull de main el
2026-11-13 y main comprobado de nuevo el 2026-11-16.
Los cambios locales de la vista sencilla se conservaron y tienen una copia en
el stash `Backup simplified interface before model v2 update 2026-11-13`.

Modelo importado: `assets/models/functiongemma-270M-sw9-v2.litertlm`.
Identidad y SHA-256: `assets/models/model.json`. La copia original de Descargas
se conserva. El modelo móvil y el servicio de Windows usan los mismos pesos.

Desde la carpeta FluffyChat_APP:

```powershell
powershell -ExecutionPolicy Bypass -File .\fluffychat-fork\scripts\run-android-assistant.ps1
```

Desde fluffychat-fork:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-android-assistant.ps1
```

Se puede añadir `-ModelFile C:\ruta\functiongemma-270M-sw9-v2.litertlm` para
importar desde otra carpeta. `-SkipBuild` reutiliza el APK existente; no sirve
para incorporar código nuevo. El script rechaza un APK anterior a la
configuración actual del modelo.

El emulador es FluffyChat_Light (Android Studio, Android 11 AOSP x86_64, 2 GB).
En Windows el motor Android no admite esta arquitectura; el modelo v2 se
ejecuta con LiteRT-LM JVM en CPU en el propio ordenador y la app accede por
`adb reverse tcp:8787 tcp:8787`. El servicio escucha solo en localhost.

La comprobación `http://127.0.0.1:8787/health` debe informar de:

- `ready: true`
- `model: functiongemma-270M-sw9-v2`
- `sha256: 37e92741110b1a7bff2607905a3598186d42de36beabe9091400879ef7d1383b`

El script reinicia el servicio antiguo de este proyecto si no coincide. La
app también rechaza un servicio que tenga otra versión o huella.

En Assistant, pulsar Set up si aparece y probar “The text is too small to read”
o “The buttons are hard to tap”. El resultado debe mostrar una vista previa;
los cambios solo se aplican tras Apply y se pueden deshacer con Undo.
Las respuestas v2 `change_text_zoom` y `change_button` se validan y se convierten
en ajustes de tamaño. No se reinterpretan valores como `high_contrast` o
`change_spacing` como cambios de tamaño.

El APK para un teléfono o emulador ARM64 incluye el archivo v2 como asset y
mantiene el motor nativo. El puente de Windows se activa únicamente en debug
con `--dart-define=SW9_EMULATOR_ASSIST=true`.

## Validacion local (2026-11-13)

- 47 pruebas aprobadas; analisis de los archivos modificados sin incidencias.
- APK debug x86_64 compilado e instalado conservando la sesion.
- El APK incluye unicamente los pesos v2 entre los modelos.
- Servicio activo con la identidad y SHA-256 v2 esperados.
- Prueba desde Assistant en el emulador: The text is too small to read
  mostro Make the text bigger? con vista previa de x1,1 a x1,2.
- La ejecucion nativa ARM64 queda pendiente de comprobar en un dispositivo
  compatible; la prueba de Windows usa el puente local descrito arriba.
