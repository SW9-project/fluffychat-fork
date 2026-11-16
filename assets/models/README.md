# Modelo SW9 v2

Modelo activo: `functiongemma-270M-sw9-v2.litertlm` (284121728 bytes).
SHA-256: `37e92741110b1a7bff2607905a3598186d42de36beabe9091400879ef7d1383b`.
El archivo fue suministrado por el equipo y se importó desde Descargas el 2026-11-13.
`model.json` registra su identidad. Los pesos no se guardan en Git.

Importar la copia descargada antes de compilar:

```sh
./scripts/fetch_personalization_model.sh /ruta/functiongemma-270M-sw9-v2.litertlm
```

En Windows, `scripts/run-android-assistant.ps1` importa por defecto desde
Descargas si falta la copia de assets. También acepta `-ModelFile RUTA`.
La importación comprueba el SHA-256. No depende de una URL de descarga del v2.

El APK incluye solo este modelo, mediante una entrada explícita en pubspec.yaml.
Los modelos anteriores y las cachés no se empaquetan con él. El nombre nuevo
hace que el motor móvil lo prepare como una versión distinta del modelo anterior.

En Android, la inferencia nativa requiere Android 11+ y ARM64. Para el emulador
x86_64 de Windows se utiliza el mismo archivo v2 en el ordenador mediante el
puente local de desarrollo. El servicio informa del nombre y SHA-256 reales;
la app comprueba ambos antes de aceptar sus respuestas.

Las funciones v2 integradas son `change_text_zoom` y `change_button`, con
`direction: bigger | smaller`. Se traducen a los ajustes existentes con límites,
vista previa, Apply y Undo. Otras funciones o argumentos se rechazan.

## Licencia

La familia FunctionGemma está sujeta a los [Gemma Terms of Use](https://ai.google.dev/gemma/terms)
y la [Gemma Prohibited Use Policy](https://ai.google.dev/gemma/prohibited_use_policy).
El archivo v2 es una modificación suministrada por el equipo SW9.
