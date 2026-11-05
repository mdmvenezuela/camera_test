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
                        Text("Diagnóstico independiente de JPEG → CVPixelBuffer")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    Button { showingImporter = true } label: {
                        HStack {
                            Image(systemName: "photo.badge.plus")
                            Text("Seleccionar JPEG")
                            Spacer()
                            Image(systemName: "arrow.up.doc")
                        }
                        .font(.headline).foregroundStyle(.white).padding(16)
                        .background(LinearGradient(colors: [.orange, .red],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(isWorking)
                    Text(fileName).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    imagePanel(title: "1 · Imagen original (UIImage)", image: originalImage)
                    imagePanel(title: "2 · Reconstruida desde CVPixelBuffer", image: pixelImage)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Diagnóstico", systemImage: "waveform.path.ecg")
                                .font(.headline).foregroundStyle(.white)
                            Spacer()
                            ShareLink(item: report) {
                                Label("Compartir", systemImage: "square.and.arrow.up")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.white)
                            }
                        }
                        Text(report)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
                            .textSelection(.enabled)
                    }
                    Text("Esta app solo importa, decodifica y analiza el archivo seleccionado. No accede a la cámara ni modifica otras aplicaciones.")
                        .font(.caption).foregroundStyle(.white.opacity(0.55)).padding(.top, 2)
                }
                .padding(20)
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.jpeg, .image],
                      allowsMultipleSelection: false, onCompletion: handleImport)
    }

    @ViewBuilder
    private func imagePanel(title: String, image: UIImage?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline).foregroundStyle(.white)
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.07))
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().padding(8)
                } else {
                    VStack(spacing: 7) {
                        Image(systemName: "photo").font(.system(size: 30))
                        Text("Sin imagen").font(.caption)
                    }.foregroundStyle(.white.opacity(0.35))
                }
            }
            .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 14))
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
                let probe = PixelBufferProbe.decode(data: data)
                if let buffer = probe.buffer {
                    let ciImage = CIImage(cvPixelBuffer: buffer)
                    if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                        pixelImage = UIImage(cgImage: cgImage)
                    }
                }
                var lines = [
                    "Archivo: \(url.lastPathComponent)",
                    "Bytes: \(data.count)",
                    "UIImage: OK · \(Int(image.size.width * image.scale)) × \(Int(image.size.height * image.scale)) px",
                    "ImageIO: \(probe.imageIOOK ? "OK" : "FALLO")",
                    "CVPixelBuffer: \(probe.buffer == nil ? "FALLO" : "OK")"
                ]
                if let buffer = probe.buffer {
                    lines.append("Dimensiones: \(CVPixelBufferGetWidth(buffer)) × \(CVPixelBufferGetHeight(buffer))")
                    lines.append("Pixel format: \(String(format: "0x%08X", CVPixelBufferGetPixelFormatType(buffer)))")
                    lines.append("BytesPerRow: \(CVPixelBufferGetBytesPerRow(buffer))")
                    lines.append("Lock base: \(probe.lockOK ? "OK" : "FALLO")")
                    lines.append("Contexto bitmap: \(probe.contextOK ? "OK" : "FALLO")")
                    lines.append("Píxeles con RGB no nulo: \(probe.nonBlackPixels)")
                    lines.append("Rango B: \(probe.minB)…\(probe.maxB) | G: \(probe.minG)…\(probe.maxG) | R: \(probe.minR)…\(probe.maxR)")
                    lines.append("Rango alfa: \(probe.minA)…\(probe.maxA)")
                    lines.append("Reconstrucción Core Image: \(pixelImage == nil ? "FALLO" : "OK")")
                } else {
                    lines.append("Detalle: \(probe.error ?? "No se pudo crear el búfer.")")
                }
                report = lines.joined(separator: "\n")
                isWorking = false
            } catch {
                isWorking = false
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
    let nonBlackPixels: Int
    let minB: Int, maxB: Int, minG: Int, maxG: Int
    let minR: Int, maxR: Int, minA: Int, maxA: Int
    let error: String?

    private static func failure(_ message: String, imageIOOK: Bool = true) -> PixelBufferProbe {
        PixelBufferProbe(buffer: nil, imageIOOK: imageIOOK, lockOK: false, contextOK: false,
                         nonBlackPixels: 0, minB: 0, maxB: 0, minG: 0, maxG: 0,
                         minR: 0, maxR: 0, minA: 0, maxA: 0, error: message)
    }

    static func decode(data: Data) -> PixelBufferProbe {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return failure("CGImageSourceCreateWithData devolvió nil.", imageIOOK: false)
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return failure("CGImageSourceCreateImageAtIndex devolvió nil.", imageIOOK: false)
        }
        let width = image.width - image.width % 2
        let height = image.height - image.height % 2
        guard width > 0, height > 0 else {
            return failure("Dimensiones inválidas después del ajuste a números pares.")
        }
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        var candidate: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA, attrs as CFDictionary, &candidate)
        guard status == kCVReturnSuccess, let buffer = candidate else {
            return failure("CVPixelBufferCreate status=\(status).")
        }
        let lockStatus = CVPixelBufferLockBaseAddress(buffer, [])
        guard lockStatus == kCVReturnSuccess else {
            return failure("CVPixelBufferLockBaseAddress status=\(lockStatus).")
        }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return failure("CVPixelBufferGetBaseAddress devolvió nil.")
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let context = CGContext(data: base, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                                                  CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return PixelBufferProbe(buffer: nil, imageIOOK: true, lockOK: true, contextOK: false,
                                    nonBlackPixels: 0, minB: 0, maxB: 0, minG: 0, maxG: 0,
                                    minR: 0, maxR: 0, minA: 0, maxA: 0,
                                    error: "CGContext no pudo crear el contexto bitmap.")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var nonBlack = 0
        var minB = 255, maxB = 0, minG = 255, maxG = 0
        var minR = 255, maxR = 0, minA = 255, maxA = 0
        for y in 0..<height {
            let row = bytes.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let offset = x * 4
                let b = Int(row[offset]), g = Int(row[offset + 1])
                let r = Int(row[offset + 2]), a = Int(row[offset + 3])
                if r != 0 || g != 0 || b != 0 { nonBlack += 1 }
                minB = min(minB, b); maxB = max(maxB, b)
                minG = min(minG, g); maxG = max(maxG, g)
                minR = min(minR, r); maxR = max(maxR, r)
                minA = min(minA, a); maxA = max(maxA, a)
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return PixelBufferProbe(buffer: buffer, imageIOOK: true, lockOK: true, contextOK: true,
                                nonBlackPixels: nonBlack, minB: minB, maxB: maxB,
                                minG: minG, maxG: maxG, minR: minR, maxR: maxR,
                                minA: minA, maxA: maxA, error: nil)
    }
}
