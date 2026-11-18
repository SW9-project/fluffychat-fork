# Tutorial de Assistant

Rama: `feat/assistant-onboarding`, desde `simple_interface_preview`.

Se abre en la primera visita a Assistant, con tres pasos cortos:

1. Assistant ayuda a adaptar la interfaz y el usuario decide los cambios.
2. Escribir una petición, pulsar Ask, revisar la preview, Apply y Undo.
3. Encontrar Settings en la barra inferior y abrir Accessibility para elegir
   los ajustes manualmente.

Tiene ilustraciones sencillas, Omitir, Atrás, Siguiente y Entendido. El último
paso permite abrir los ajustes reales de accesibilidad. No cambia preferencias
de accesibilidad, no prepara el modelo ni envía peticiones al asistente.

## Repetirlo en las pruebas

En Settings, junto a Accessibility, están `Assistant tutorial / View tutorial`
para verlo ahora y `Show on next Assistant visit` para activar o desactivar
su apertura automática. Antes de cada participante, activar este interruptor
y abrir Assistant. También se puede repetir con el botón de ayuda en Assistant.

Terminar, omitir o cerrar el tutorial desactiva su apertura automática.
La preferencia es local a la instalación (`assistant_tutorial.pending.v1`),
compartida por sus cuentas. No se borran sesiones ni ajustes al repetirlo.

Los botones tienen texto y un área mínima de 48 dp; se mantienen los tamaños
personalizados. El contenido se desplaza con letra grande, las acciones se
reparten en varias filas y se anuncian los títulos de cada paso al lector de
pantalla. Las ilustraciones decorativas no duplican el contenido hablado.
Textos en inglés, español y danés; los nombres de los ajustes coinciden con
los que muestra la aplicación.

## Validación

69 pruebas aprobadas del tutorial, Assistant, Simple view, preview y
accesibilidad. Las cinco pruebas específicas cubren primera visita, omitir,
persistencia, repetición desde Settings, apertura explícita de los ajustes
y pantalla de 320 × 640 con texto al 200 %.

Analisis estatico sin incidencias. APK compilado e instalado en FluffyChat_Light.
Revision visual de los tres pasos y comprobacion de que completar desactiva
la apertura automatica y el interruptor de Settings la reactiva para la
siguiente visita. Tutorial dejado abierto en el primer paso.
