# nVital
Portable hardware diagnostic tool for Macs. Runs from USB, no install needed. Tests Wi-Fi, Bluetooth, battery, storage, camera, audio, keyboard, trackpad and display, and generates a pass/fail report. macOS 10.13+ · Intel &amp; Apple Silicon.

## Estructura

El proyecto está dividido en dos módulos para poder integrarlo más adelante en una suite de herramientas:

```
nVital/
├── project.yml                 # Especificación XcodeGen (genera nVital.xcodeproj)
├── Package.swift               # NVitalCore como Swift Package, para otras apps de la suite
├── Configs/Shared.xcconfig     # Prefijo de bundle ID, versión, despliegue 10.13, arquitecturas
├── Scripts/make_app_icon.py    # Dibuja el icono (requiere Pillow: pip install pillow)
├── NVitalCore/                 # Framework: lógica de diagnóstico, sin AppKit
│   ├── Sources/
│   │   ├── Model/              # Protocolo DiagnosticTest, resultados, contexto, interacción
│   │   ├── Runner/             # DiagnosticRunner y la lista de pruebas estándar
│   │   ├── Diagnostics/        # Wi-Fi, Bluetooth, batería, almacenamiento, cámara,
│   │   │                       # altavoces, micrófono, teclado, trackpad, pantalla
│   │   ├── Report/             # DiagnosticReport y exportación HTML / texto / JSON
│   │   └── System/             # IOKit, sysctl, diskutil, permisos
│   └── Tests/                  # Tests unitarios (XCTest)
└── nVital/                     # App: solo interfaz AppKit, usa NVitalCore
    ├── Sources/
    │   ├── App/                # main.swift, AppDelegate, menú
    │   ├── Main/               # Ventana principal y exportación del informe
    │   └── Interaction/        # Hojas de las pruebas interactivas
    ├── Assets.xcassets/        # Icono de la app
    └── Resources/              # Info.plist y entitlements
```

| Target | Tipo | Bundle ID |
| --- | --- | --- |
| `NVitalCore` | Framework | `com.nil.nvital.core` |
| `nVital` | App | `com.nil.nvital` |

El prefijo `com.nil` se define una sola vez en `Configs/Shared.xcconfig` (`NVITAL_BUNDLE_ID_PREFIX`). Si usas tu propio dominio, cámbialo ahí.

### NVitalCore

- **`DiagnosticTest`**: protocolo que implementa cada prueba (`identifier`, `name`, `category`, `run(in:completion:)`, `cancel()`…). Usa *completion handlers* en lugar de `async/await` porque la concurrencia de Swift necesita macOS 10.15.
- **`DiagnosticRunner`**: ejecuta las pruebas en orden, aplica un tiempo límite a las automáticas, admite cancelación y guarda el último resultado de cada una.
- **`DiagnosticInteractionHandler`**: lo implementa la app. Las pruebas que necesitan al usuario (pulsar teclas, mirar la pantalla, escuchar un tono) piden la interacción con `context.request(_:)` y el framework no sabe nada de la interfaz.
- **`DiagnosticReport` / `ReportRenderer`**: informe con identificación del equipo (modelo, serie, procesador, memoria, macOS) y exportación a HTML, texto o JSON.

Para añadir una prueba a la suite basta con crear una clase que cumpla `DiagnosticTest` y pasarla a `DiagnosticRunner(tests:)`.

## Compilar

Requisitos: Xcode 15 o posterior y [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open nVital.xcodeproj
```

Desde la línea de comandos:

```sh
xcodebuild -project nVital.xcodeproj -scheme nVital -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build ONLY_ACTIVE_ARCH=NO
```

El binario es universal (x86_64 + arm64) con despliegue mínimo macOS 10.13. Los tests del framework también se pueden ejecutar sin Xcode con `swift test`.

## Usar desde un USB

Copia `nVital.app` al USB y ábrela desde ahí; no se instala nada en el Mac. El informe se guarda por defecto en la misma carpeta que la app.

Por defecto la app se firma *ad hoc*. Si macOS la bloquea en otro equipo, quita la cuarentena antes de abrirla:

```sh
xattr -dr com.apple.quarantine /Volumes/USB/nVital.app
```

Para distribuirla sin ese paso, fírmala con un certificado Developer ID y notarízala (el *hardened runtime* ya está activado).

### Permisos

Al abrir nVital se piden seguidos todos los permisos que falten, para que ninguna prueba se interrumpa después:

- **Cámara, micrófono y Bluetooth**: sin ellos, esas pruebas dan error.
- **Accesibilidad** (opcional): en la prueba de teclado permite bloquear los atajos del sistema (F11 «Mostrar escritorio», ⌘Tab, Spotlight…) para que todas las pulsaciones lleguen a nVital. Se pide al abrir la app solo la primera vez en cada Mac, porque macOS repetiría el aviso en cada arranque. Sin este permiso, la prueba funciona igual, pero una tecla de función que no se detecte se marca como aviso en vez de como fallo.

En **nVital › Permisos…** se ve el estado de cada uno, se pueden volver a pedir los que falten y se abre Ajustes del Sistema para activar los denegados (macOS no vuelve a preguntar por un permiso denegado).

Durante la prueba de teclado, la fila superior pasa a enviar F1–F12 (como la opción «Usar F1, F2, etc. como teclas de función estándar»), así que no cambia el brillo ni el volumen ni abre Mission Control. Al terminar se vuelve al modo elegido en Ajustes del Sistema. Si la app se cierra de forma inesperada durante la prueba, se restaura al volver a abrirla o al reiniciar sesión.

Como la app se firma *ad hoc*, cada compilación nueva es otra app para macOS: puede que tengas que volver a conceder los permisos tras recompilar.
