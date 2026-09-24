//
//  A stand-in for the class Xcode generates from PhotoThemes.mlpackage.
//
//  Used only by Tools/typecheck.sh and never compiled into the app. The generated class
//  does not exist outside a real build, so a bare compiler invocation cannot see it — and
//  leaving PhotoThemeIndex out of the typecheck instead is no good, because the engine
//  refers to it and the errors simply move somewhere else.
//
//  It declares exactly the surface the app uses: a configuration initialiser, a prediction
//  taking a pixel buffer, and an embedding on the result. If the app starts using more of
//  the model than this, the typecheck fails here — which is the right failure, because it
//  means this file has drifted from the model it stands in for.
//

import CoreML
import CoreVideo

final class PhotoThemes {
    init(configuration: MLModelConfiguration) throws {}

    func prediction(image: CVPixelBuffer) throws -> PhotoThemesOutput {
        throw NSError(domain: "typecheck-only", code: 0)
    }
}

final class PhotoThemesOutput {
    var embedding: MLMultiArray { fatalError("typecheck only") }
}
