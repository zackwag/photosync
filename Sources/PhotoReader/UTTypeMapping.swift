import Foundation

/// Maps UTI strings to file extensions for Skylight upload.
public func extensionForUTType(_ uti: String) -> String {
    switch uti {
    case "public.jpeg", "public.jpg": "jpg"
    case "public.png": "png"
    case "public.heic": "heic"
    case "public.heif": "heic" // Skylight accepts heic; heif is the container format
    case "public.gif": "gif"
    case "public.webp": "webp"
    default: "jpg" // safe fallback — re-encode as JPEG if needed
    }
}
