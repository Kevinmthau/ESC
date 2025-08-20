import SwiftUI
import PDFKit

struct NativePDFView: UIViewRepresentable {
    let pdfData: Data
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.usePageViewController(false)
        
        if let document = PDFDocument(data: pdfData) {
            pdfView.document = document
            print("📄 PDF loaded: \(document.pageCount) pages")
        } else {
            print("📄 Failed to create PDF document from data")
        }
        
        return pdfView
    }
    
    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document == nil {
            if let document = PDFDocument(data: pdfData) {
                pdfView.document = document
            }
        }
    }
}