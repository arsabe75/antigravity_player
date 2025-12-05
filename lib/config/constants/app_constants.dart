/// Constantes globales de la aplicación
class AppConstants {
  AppConstants._();

  // ============================================
  // Duraciones
  // ============================================

  /// Tiempo antes de ocultar los controles del reproductor
  static const controlsHideDelay = Duration(seconds: 3);

  /// Duración del seek con flechas del teclado
  static const seekDuration = Duration(seconds: 10);

  /// Intervalo de actualización de la posición del video
  static const positionUpdateInterval = Duration(milliseconds: 200);

  /// Delay antes de dispose para limpiar recursos
  static const disposeDelay = Duration(milliseconds: 100);

  /// Duración de la animación de fade de los controles
  static const controlsFadeDuration = Duration(milliseconds: 300);

  // ============================================
  // Tamaños de ventana
  // ============================================

  /// Tamaño inicial de la ventana
  static const defaultWindowWidth = 800.0;
  static const defaultWindowHeight = 600.0;

  /// Altura de la barra superior
  static const topBarHeight = 40.0;

  // ============================================
  // Iconos
  // ============================================

  /// Tamaño de los iconos en las barras de control
  static const iconSize = 20.0;

  /// Tamaño del icono del logo en home
  static const logoIconSize = 64.0;

  // ============================================
  // Volumen
  // ============================================

  /// Volumen por defecto
  static const defaultVolume = 1.0;

  /// Volumen mínimo
  static const minVolume = 0.0;

  /// Volumen máximo
  static const maxVolume = 1.0;

  /// Incremento/decremento de volumen con teclado
  static const volumeStep = 0.1;

  // ============================================
  // Velocidad de reproducción
  // ============================================

  /// Velocidad por defecto
  static const defaultPlaybackSpeed = 1.0;

  /// Velocidades disponibles
  static const playbackSpeeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  // ============================================
  // Slider del reproductor
  // ============================================

  /// Altura del track del slider
  static const sliderTrackHeight = 2.0;

  /// Radio del thumb del slider de progreso
  static const progressThumbRadius = 6.0;

  /// Radio del overlay del slider de progreso
  static const progressOverlayRadius = 12.0;

  /// Radio del thumb del slider de volumen
  static const volumeThumbRadius = 4.0;

  /// Ancho del control de volumen
  static const volumeSliderWidth = 100.0;

  // ============================================
  // Botones
  // ============================================

  /// Ancho de los botones principales en home
  static const mainButtonWidth = 250.0;

  /// Alto de los botones principales en home
  static const mainButtonHeight = 50.0;

  // ============================================
  // Historial y persistencia
  // ============================================

  /// Máximo de URLs recientes a guardar
  static const maxRecentUrls = 10;

  /// Máximo de videos recientes a guardar
  static const maxRecentVideos = 50;

  /// Intervalo para guardar posición automáticamente (en segundos)
  static const autoSavePositionInterval = 5;

  // ============================================
  // Texto
  // ============================================

  /// Nombre de la aplicación
  static const appName = 'Antigravity Player';
}
