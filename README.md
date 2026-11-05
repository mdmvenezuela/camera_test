# VCAM Photo Test (app independiente)

Esta app **no modifica ni se enlaza con el tweak**. Sirve para probar, de forma aislada, si un JPEG seleccionado puede:
1. abrirse como `UIImage`;
2. decodificarse mediante ImageIO;
3. convertirse a un `CVPixelBuffer` BGRA;
4. volver a mostrarse desde ese `CVPixelBuffer`.

## Uso
1. Compila el proyecto con el workflow de GitHub Actions (o desde Xcode).
2. Instala el IPA con Sideloadly/AltStore usando tu Apple ID.
3. En el iPhone, abre la app y pulsa **Seleccionar JPEG**.
4. Importa `vcam_temp.jpg` desde Archivos. Si todavía está en `/rootfs/private/var/tmp`, compártelo desde Filza a Archivos primero.
5. Revisa los indicadores y captura una pantalla con el resultado.

## Qué demuestra
- Si la imagen original y la imagen reconstruida desde el PixelBuffer se ven, la decodificación JPEG y la conversión aislada funcionan para ese archivo.
- Si la original se ve y el PixelBuffer falla, el problema está en la conversión aislada.
- Si ambas fallan, revisa el archivo importado/formato.

La app informa el estado de cada paso, dimensiones, formato y `bytesPerRow`. No accede a `/var/tmp` directamente porque una app iOS normal está aislada por sandbox.

## Proyecto
Abre `VCAMPhotoTest.xcodeproj` en Xcode. Deployment target: iOS 15.0.
