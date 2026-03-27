# Antigravity Player

Antigravity Player es una potente aplicación de escritorio diseñada para reproducir videos locales y transmitir contenido multimedia directamente desde Telegram de forma fluida y nativa.

La aplicación permite integrar tus cuentas de Telegram y el contenido local en una única experiencia inmersiva, utilizando reproductores de video altamente optimizados (`media_kit` y `FVP`). Está especialmente diseñada para facilitar la administración y el acceso rápido a los canales y grupos que más sigues, asegurando una reproducción estable y llena de características avanzadas.

---

## ⚙️ Requisitos del Sistema y Ejecución

### Para Windows
- **Sistema Operativo**: Windows 10 o superior (64 bits).
- **Librerías**: No se requiere la instalación de librerías adicionales para ejecutar. El reproductor viene con todos los códecs necesarios integrados para funcionar correctamente ("Out of the box").

### Para Linux (ej. Kubuntu, Ubuntu, Debian)
Para asegurar el correcto funcionamiento de los motores de reproducción integrados, especialmente `media_kit` (que se basa en `mpv` y FFmpeg), es fundamental instalar las siguientes dependencias del sistema antes de ejecutar la aplicación.

Abre una terminal y ejecuta:
```bash
sudo apt update
sudo apt install libmpv-dev mpv ffmpeg libavcodec-dev libavformat-dev libavutil-dev
```
*(Nota: Dependiendo de la distribución, el nombre exacto de los paquetes de las librerías puede variar. Garantizar la instalación de `libmpv-dev` es esencial).*

---

## 🚀 Guía de Uso y Navegación de Pantallas

La aplicación está dividida en varias secciones clave accesibles desde su interfaz de navegación:

### 1. Gestión de Cuenta de Telegram
- **Acceder a una cuenta**: Utiliza la interfaz de login o acceso principal para introducir tu cuenta y código de autenticación (o código QR si está soportado en la versión en uso). Esto sincroniza inmediatamente el listado de tus chats.
- **Salir (Log out)**: Puedes cerrar sesión de Telegram fácilmente desde el menú de opciones o la configuración de la cuenta, lo cual eliminará tus datos locales de manera segura y protegerá tu privacidad.

### 2. Canales, Grupos Favoritos y Pantalla Principal
- En la interfaz principal, la aplicación carga y visualiza tu lista de chats, organizándolos por tipo.
- **Fijar o Seleccionar Favoritos**: Existen botones dedicados dentro de la interfaz de canales y grupos que permiten "Guardar" o marcarlos como favoritos. Utilizar esta función facilitará el acceso priorizado a estos chats directamente desde el inicio sin tener que buscarlos cada vez.

### 3. Configuración y Selección de Reproductores
- **Seleccionar el Reproductor de Video**: En los ajustes o configuración interna, puedes alternar el motor de reproducción principal. Elige entre **`media_kit`** (altamente optimizado, moderno y soporta selección de pistas) o **`FVP`** (alternativa liviana excelente para compatibilidad de hardware específico).
- **Administrar Almacenamiento de Telegram**: A medida que reproduces videos remotos de Telegram, se descargan en la memoria caché del dispositivo. La app incorpora una **Pantalla de Almacenamiento (Telegram Storage)** que te muestra gráficas de uso y te da botones para vaciar dichos archivos temporales. Esto previene saturaciones de disco.

---

## 🎬 Uso del Reproductor de Video Integrado

Una vez inicias la reproducción (ya sea de un archivo local o de un chat de Telegram), accederás a la **Pantalla de Reproducción (Player Screen)**. Ésta integra útiles controles superpuestos y amplios atajos de teclado para uso ágil.

### Botones Activos en el Reproductor (Visuales)
- **Top Bar (Barra Superior)**: 
  - **Atrás/Cerrar**: Para volver a la lista de videos o salir del reproductor de forma segura.
  - Título y nombre del contenido visualizado.
- **Play / Pausa**: Inicia o interrumpe la reproducción actual.
- **Siguiente / Anterior**: Permite moverse directamente entre próximos videos dentro de la misma lista de reproducción de Telegram.
- **Barra de Progreso (Seek Bar)**: Visualiza el tiempo transcurrido. Puedes dar clic en cualquier punto para adelantar/retroceder.
- **Volumen y Silenciar (Mute)**: Controles de barra y botón rápido para enmudecer el sonido.
- **Fullscreen (Pantalla Completa)**: Botón para alternar la visualización llenando toda la pantalla del monitor.
- **Always on Top (Botón Fijo/PiP)**: Configura la ventana para que flote por encima del resto de programas abiertos del sistema.
- **Mirror (Modo Espejo)**: Da la vuelta de forma horizontal a la imagen actual en reproducción.
- **Playlist (Alternar Lista)**: Un botón para abrir un panel lateral (Sidebar) donde puedes ver visualmente los siguientes videos formados en la cola y pre-seleccionarlos con el mouse.
- **Selector de Pistas (Tracks)**: _(Disponible principalmente cuando usas `media_kit`)_. Abre un selector inferior para elegir entre pistas multilenguaje de **Audio**, canales de **Subtítulos** incrustados, o resolución.

### Atajos de Teclado Rápidos

Para obtener la experiencia completa con el teclado, aquí tienes todos los comandos soportados en el reproductor:

| Acción | Tecla(s) Rápidas | Teclas Multimedia (Opcionales) |
| :--- | :--- | :--- |
| **Play / Pausa** | `Espacio` o `K` | Botón _Play/Pause_ |
| **Pantalla Completa (Alternar)** | `F` | - |
| **Salir de Pantalla Completa** | `Esc` (Escape) | - |
| **Detener Video / Volver Atrás** | `S` | - |
| **Saltar al Siguiente Video** | `N` o el símbolo `°` (Grados) | Botón _Próximo_ |
| **Volver al Video Anterior** | `P` o el símbolo `±` (Más/Menos) | Botón _Anterior_ |
| **Avanzar normal (Salto largo)** | `L` | - |
| **Retroceder normal (Salto largo)**| `J` | - |
| **Avanzar rápido (Salto corto/fino)** | `Flecha Derecha` | - |
| **Retroceder (Salto corto/fino)** | `Flecha Izquierda` | - |
| **Subir Volumen** | `Flecha Arriba` | - |
| **Bajar Volumen** | `Flecha Abajo` | - |
| **Silenciar Audio (Mute)** | `M` | - |
| **Activar Modo Espejo (Mirror)** | `E` | - |
| **Saltar a porcentaje específico** | Teclas `0` (Arranque) al `9` (90%) | - |

> **Nota Crítica**: Si tu sistema se está quedando peligrosamente sin espacio en el disco duro por reproducir contenido en caché de Telegram, el reproductor mostrará un banner fijo rojo en la zona superior izquierda ("Critical Disk Space"). En tal caso, se interrumpirán descargas para proteger tu OS y se recomienda dirigirse al botón administrador de almacenamiento para limpiar la caché del programa.
