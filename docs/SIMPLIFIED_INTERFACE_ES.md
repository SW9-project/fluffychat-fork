# Vista sencilla personalizada

Rama: `simple_interface`, creada desde main actualizado. Incluye la vista sencilla y la integracion del modelo v2.

## Flujo

- Primera activación desde Chats o Assistant: tres preguntas y una vista previa; solo se guarda al pulsar **Apply this view**.
- Activaciones posteriores desde el interruptor: vista previa antes de cambiar, tanto al activar como al desactivar.
- **Do not show this preview again...** permite usar el interruptor directamente en adelante. Se puede recuperar desmarcando la casilla en **Personalize**.
- **Personalize** vuelve a abrir las tres preguntas para cambiar las preferencias.
- Cancelar, volver atrás o cerrar el diálogo no guarda respuestas parciales ni la casilla de vista previa.
- Assistant mantiene su propia confirmación y Undo, aunque se omita la vista previa del interruptor. Si aún no se ha completado la configuración, Apply abre el cuestionario.

## Tres elecciones

1. Accesos superiores: tres conversaciones más abiertas desde Chats en este dispositivo, hasta tres elegidas manualmente, o ninguno. La opción automática empieza con las recientes hasta tener datos de uso; no analiza mensajes, descarga historial ni consulta contactos. Los recuentos y las selecciones se separan por cuenta.
2. Lista de conversaciones: tarjetas con nombres y sin leer, sin avances, fechas ni marcas de lectura; o conservar la información habitual.
3. Chat: fondo liso, menos información secundaria y emojis agrupados con adjuntos; o conservar el chat habitual. Los avisos de conexión y seguridad siguen disponibles.

El modo sencillo tiene un encabezado destacado, fondo suave y tarjetas diferenciadas. Los accesos aparecen encima del resto y fuera de sus filtros. Los filtros siguen afectando a la lista inferior. Al desactivar se recupera la vista completa sin borrar los fondos ni los contactos elegidos.

Los cambios no modifican las preferencias globales de tamaños de texto/botones ni la densidad de mensajes del MVP.

## Modelo y ejecución

El modelo activo es `functiongemma-270M-sw9-v2.litertlm`. La integración de texto y botones usa sus herramientas v2. La vista sencilla mantiene su acción explícita en Assistant y su contrato `change_interface({view: "simple" | "full"})`; otras herramientas del modelo no se aplican sin una implementación y validación correspondientes.

Desde FluffyChat_APP:

```powershell
powershell -ExecutionPolicy Bypass -File .\fluffychat-fork\scripts\run-android-assistant.ps1
```

`-SkipBuild` reutiliza un APK existente y no incorpora cambios nuevos de código. En Windows x86 el modelo sigue ejecutándose localmente en el ordenador mediante el puente de desarrollo.

## Referencia

[Estudio exploratorio de Frontiers (2026)](https://www.frontiersin.org/journals/communication/articles/10.3389/fcomm.2026.1808537/full). Las elecciones son voluntarias y reversibles; el diseño todavía necesita evaluación con usuarios mayores.

## Validación

40 pruebas pasadas: configuración, cancelación, persistencia, omisión y recuperación de vistas previas, funcionamiento con texto al 200 %, separación por cuenta, primera activación desde Assistant y Undo. Análisis de código sin incidencias.

Instalada y abierta en FluffyChat_Light conservando la sesión. Revisados visualmente el cuestionario y la vista previa antes de aplicar; se dejó la primera pregunta abierta sin guardar elecciones de prueba.
