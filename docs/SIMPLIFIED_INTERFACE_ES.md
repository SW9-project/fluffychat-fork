# Vista sencilla personalizada

## Flujo

- Primera activación desde Chats o Assistant: dos preguntas y una vista previa; solo se guarda al pulsar **Apply / Aplicar**.
- Activaciones posteriores desde el interruptor: vista previa antes de cambiar, tanto al activar como al desactivar.
- **Skip preview next time** permite usar el interruptor directamente en adelante. Se puede recuperar desmarcando la casilla en **Change / Cambiar**.
- **Change / Cambiar** vuelve a abrir las dos preguntas para cambiar las preferencias.
- Cancelar, volver atrás o cerrar el diálogo no guarda respuestas parciales ni la casilla de vista previa.
- Assistant mantiene su propia confirmación y Undo, aunque se omita la vista previa del interruptor. Si aún no se ha completado la configuración, Apply abre el cuestionario.

## Dos elecciones

1. Accesos superiores: las tres conversaciones más abiertas desde Chats en este dispositivo, hasta tres elegidas manualmente, o ninguna. La opción automática empieza con las recientes hasta tener datos de uso; no analiza mensajes, no descarga historial ni consulta contactos. Los recuentos y las selecciones se guardan por cuenta.
2. Lista de conversaciones: tarjetas con nombre y mensajes sin leer, sin avances, fechas ni marcas de lectura; o conservar la información habitual.

Mientras el modo está activo, el chat usa más separación entre mensajes e interlineado de 1,5, y oculta en la cabecera la línea de conexión («activo», «visto hace…»); los errores de sincronización se siguen mostrando. El modo respeta los tamaños de texto, botones y zonas táctiles guardados.

## Assistant

Cuando el modelo propone `set_simple_mode`, o `reset_settings` con `simple_mode`, Assistant muestra la vista previa de la vista sencilla en lugar de aplicar el cambio directamente.

## Referencia

[Estudio exploratorio de Frontiers (2026)](https://www.frontiersin.org/journals/communication/articles/10.3389/fcomm.2026.1808537/full). Las elecciones son voluntarias y reversibles; el diseño todavía necesita evaluación con usuarios mayores.
