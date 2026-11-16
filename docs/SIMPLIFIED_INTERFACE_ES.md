# Vista sencilla personalizada

Rama: `simple_interface`, creada desde main actualizado. Incluye la vista sencilla y la integracion del modelo v2.

## Flujo

- Primera activación desde Chats o Assistant: dos preguntas y una vista previa; solo se guarda al pulsar **Apply / Aplicar**.
- Activaciones posteriores desde el interruptor: vista previa antes de cambiar, tanto al activar como al desactivar.
- **Skip preview next time** permite usar el interruptor directamente en adelante. Se puede recuperar desmarcando la casilla en **Change / Cambiar**.
- **Change / Cambiar** vuelve a abrir las dos preguntas para cambiar las preferencias.
- Cancelar, volver atrás o cerrar el diálogo no guarda respuestas parciales ni la casilla de vista previa.
- Assistant mantiene su propia confirmación y Undo, aunque se omita la vista previa del interruptor. Si aún no se ha completado la configuración, Apply abre el cuestionario.

## Dos elecciones

1. Accesos superiores: los nombres se eligen durante este paso, sin guardar hasta Aplicar. La opcion automatica muestra los tres nombres justo debajo de la opcion elegida. Se permiten tres conversaciones más abiertas desde Chats en este dispositivo, hasta tres elegidas manualmente, o ninguno. La opción automática empieza con las recientes hasta tener datos de uso; no analiza mensajes, descarga historial ni consulta contactos. Los recuentos y las selecciones se separan por cuenta.
2. Lista de conversaciones: tarjetas con nombres y sin leer, sin avances, fechas ni marcas de lectura; o conservar la información habitual.

El chat sencillo se activa siempre con el modo: fondo liso, 20 dp de separacion
entre mensajes, mas relleno interior e interlineado de 1,5. Se ocultan horas y
marcas de lectura habituales, la fila de lectores, los indicadores de escritura
y las insignias de rol. Al seleccionar un mensaje reaparecen sus metadatos;
los estados de envio/error y los avisos de seguridad siguen disponibles.
Los fondos y ajustes de la vista completa se recuperan al desactivar el modo.

El control superior es una fila discreta con interruptor y Cambiar. El modo sencillo usa fondo suave, tarjetas claras y bordes discretos. Los accesos aparecen encima del resto y fuera de sus filtros. Los filtros siguen afectando a la lista inferior. Al desactivar se recupera la vista completa sin borrar los fondos ni los contactos elegidos.

El modo respeta los tamanos de texto, botones y zonas tactiles guardados. Los dialogos conservan la escala del usuario y del sistema sin duplicarla. La separacion adicional del chat se presenta solo mientras el modo esta activo.

## Modelo y ejecución

El modelo activo es `functiongemma-270M-sw9-v2.litertlm`. La integración de texto y botones usa sus herramientas v2. La vista sencilla mantiene su acción explícita en Assistant y su contrato `change_interface({view: "simple" | "full"})`; otras herramientas del modelo no se aplican sin una implementación y validación correspondientes.

Desde FluffyChat_APP:

```powershell
powershell -ExecutionPolicy Bypass -File .\fluffychat-fork\scripts\run-android-assistant.ps1
```

`-SkipBuild` reutiliza un APK existente y no incorpora cambios nuevos de código. En Windows x86 el modelo sigue ejecutándose localmente en el ordenador mediante el puente de desarrollo.

## Referencia

[Estudio exploratorio de Frontiers (2026)](https://www.frontiersin.org/journals/communication/articles/10.3389/fcomm.2026.1808537/full). Las elecciones son voluntarias y reversibles; el diseño todavía necesita evaluación con usuarios mayores.

## Validacion

Pruebas de configuracion, cancelacion, persistencia, vistas previas, cuentas,
Assistant con Apply/Undo y conservacion de los tamanos personalizados.
La prueba del renderizador real del chat comprueba el mayor interlineado y
su restauracion al desactivar, manteniendo el texto al 180 %.
Las pruebas del asistente y accesibilidad siguen cubriendo el flujo anterior.

Revision del 2026-11-16: configuracion reducida a dos pasos, control superior
compacto, nombres elegibles dentro del primer paso y chat sencillo automatico.
Pruebas: 66 de interfaz/accesibilidad aprobadas y 1 del renderizador real del
chat aprobada. Tras el ajuste visual final se repitieron las 21 de vista
sencilla; analisis final sin incidencias.

Revision visual final en FluffyChat_Light: control compacto, tarjetas claras,
tres nombres visibles bajo la opcion automatica, dos pasos y vista previa
con el ejemplo de chat espaciado. Se conservaron las preferencias existentes.
Prueba adicional aprobada: desplazar la vista previa arrastrando dentro de
la tarjeta de ejemplo. No se guardaron elecciones de prueba.
