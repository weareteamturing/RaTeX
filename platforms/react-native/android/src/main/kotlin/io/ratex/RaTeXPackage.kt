// RaTeXPackage.kt — ReactPackage registration for RaTeX React Native module.

package io.ratex

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager

class RaTeXPackage : ReactPackage {
    override fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> =
        emptyList()

    override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> {
        // Must precede the first render: the Rust core caches its Unicode fallback font once.
        RaTeXUnicodeFont.configureFromManifest(reactContext)
        return listOf<ViewManager<*, *>>(
            RaTeXViewManager(reactContext),
            RaTeXInlineViewManager(reactContext),
        )
    }
}
