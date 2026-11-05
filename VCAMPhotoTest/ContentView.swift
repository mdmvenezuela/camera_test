import SwiftUI
import UniformTypeIdentifiers
import CoreImage
import CoreVideo
import ImageIO
import CoreGraphics

struct ContentView: View {
    @State private var showingImporter = false
    @State private var originalImage: UIImage?
    @State private var pixelImage: UIImage?
    @State private var report = "Selecciona vcam_temp.jpg para comenzar."
    @State private var fileName = "Ningún archivo seleccionado"
    @State private var isWorking = false

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.055, green: 0.075, blue: 0.13),
                                    Color(red: 0.10, green: 0.13, blue: 0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("VCAM Photo Test")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Prueba independiente de JPEG → CVPixelBuffer")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "photo.badge.plus")
                            Text("Seleccionar JPEG")
                            Spacer()
                            Image(systemName: "arrow.up.doc")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(isWorking)

                    Text(fileName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)

                    imagePanel(title: "1 · Imagen original (UIImage)", image: originalImage)
                    imagePanel(title: "2 · Reconstruida desde CVPixelBuffer", image: pixelImage)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Diagnóstico", systemImage: "waveform.path.ecg")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(report)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
                            .textSelection(.enabled)
                    }

                    Text("La app solo prueba el archivo que importas. No intercepta cámaras ni modifica otras aplicaciones.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 2)
                }
                .padding(20)
            }
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.jpeg, .image],
                      allowsMultipleSelection: false,
                      onCompletion: handleImport)
    }

    @ViewBuilder
    private func imagePanel(title: String, image: UIImage?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.07))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    VStack(spacing: 7) {
                        Image(systemName: "photo")
                            .font(.system(size: 30))
                        Text("Sin imagen")
                            .font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.35))
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            report = "ERROR al importar: \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                fileName = "\(url.lastPathComponent) · \(data.count) bytes"
                guard let image = UIImage(data: data) else {
                    originalImage = nil
                    pixelImage = nil
                    report = "FALLO UIImage(data:). El archivo no pudo abrirse como imagen."
                    return
                }

                originalImage = image
                pixelImage = nil
                isWorking = true
                let result = PixelBufferProbe.decode(data: data)
                if let buffer = result.buffer {
                    let ciImage = CIImage(cvPixelBuffer: buffer)
                    if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                        pixelImage = UIImage(cgImage: cgImage)
                    }
                }

                var lines = [
                    "Archivo: \(url.lastPathComponent)",
                    "Bytes: \(data.count)",
                    "UIImage: OK · \(Int(image.size.width * image.scale)) × \(Int(image.size.height * image.scale)) px",
                    "ImageIO: \(result.imageIOOK ? "OK" : "FALLO")",
                    "CVPixelBuffer: \(result.buffer == nil ? "FALLO" : "OK")"
                ]
                if let buffer = result.buffer {
                    lines.append("Dimensiones buffer: \(CVPixelBufferGetWidth(buffer)) × \(CVPixelBufferGetHeight(buffer))")
                    lines.append("Pixel format: \(String(format: "0x%08X", CVPixelBufferGetPixelFormatType(buffer)))")
                    lines.append("BytesPerRow: \(CVPixelBufferGetBytesPerRow(buffer))")
                    lines.append("Lock base: \(result.lockOK ? "OK" : "FALLO")")
                    lines.append("Contexto bitmap: \(result.contextOK ? "OK" : "FALLO")")
                    lines.append("Imagen reconstruida: \(pixelImage == nil ? "FALLO" : "OK")")
                } else {
                    lines.append("Detalle: \(result.error ?? "No se pudo crear el búfer.")")
                }
                report = lines.joined(separator: "\n")
                isWorking = false
            } catch {
                report = "ERROR leyendo archivo: \(error.localizedDescription)"
            }
        }
    }
}

private struct PixelBufferProbe {
    let buffer: CVPixelBuffer?
    let imageIOOK: Bool
    let lockOK: Bool
    let contextOK: Bool
    let error: String?

    static func decode(data: Data) -> PixelBufferProbe {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return .init(buffer: nil, imageIOOK: false, lockOK: false, contextOK: false,
                         error: "CGImageSourceCreateWithData devolvió nil.")
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return .init(buffer: nil, imageIOOK: false, lockOK: false, contextOK: false,
                         error: "CGImageSourceCreateImageAtIndex devolvió nil.")
        }

        let width = image.width - (image.width % 2)
        let height = image.height - (image.height % 2)
        guard width > 0, height > 0 else {
            return .init(buffer: nil, imageIOOK: true, lockOK: false, contextOK: false,
                         error: "Dimensiones inválidas después del ajuste a números pares.")
        }

        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        var optionalBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA,
                                         attrs as CFDictionary, &optionalBuffer)
        guard status == kCVReturnSuccess, let buffer = optionalBuffer else {
            return .init(buffer: nil, imageIOOK: true, lockOK: false, contextOK: false,
                         error: "CVPixelBufferCreate status=\(status).")
        }

        let lockStatus = CVPixelBufferLockBaseAddress(buffer, [])
        guard lockStatus == kCVReturnSuccess,
              let base = CVPixelBufferGetBaseAddress(buffer),
              let colorSpace = CGColorSpaceCreateDeviceRGB() as CGColorSpace? else {
            if lockStatus == kCVReturnSuccess { CVPixelBufferUnlockBaseAddress(buffer, []) }
            return .init(buffer: nil, imageIOOK: true, lockOK: false, contextOK: false,
                         error: "No se pudo bloquear u obtener base address/color space.")
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let context = CGContext(data: base, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                                                  CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return .init(buffer: nil, imageIOOK: true, lockOK: true, contextOK: false,
                         error: "CGContext no pudo crear el contexto bitmap.")
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return .init(buffer: buffer, imageIOOK: true, lockOK: true, contextOK: true, error: nil)
    }
}
