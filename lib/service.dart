// Importamos dart:io para poder manejar y leer archivos locales, como las imágenes de la memoria del teléfono.
import 'dart:io';
// Importamos el paquete de manipulación de imágenes y le damos el alias 'img' para no confundir con los Widgets de Flutter.
import 'package:image/image.dart' as img;
// Importamos las dependencias oficiales de TensorFlow Lite para Flutter, que nos permiten cargar modelos y hacer inferencias.
import 'package:tflite_flutter/tflite_flutter.dart';
// Importamos el logger para poder imprimir en la consola información estructurada, advertencias y errores.
import 'package:logger/logger.dart';

// Creamos una clase servicio para encapsular toda la lógica de los modelos de TensorFlow (separación de responsabilidades).
class TFService {
  // Declaramos la variable en la que se alojará y gestionará nuestro modelo TFLite nativo. Usa "?" porque inicia nula.
  Interpreter? _interpreter;

  // Instanciamos el logger particular para este archivo/servicio.
  var customLogger = Logger(
    // Configuramos cómo se verán los logs generados en consola.
    printer: PrettyPrinter(
      // Número de líneas del rastro de código mostrado en log normal.
      methodCount: 2,
      // Número de líneas en caso de que sea un log de error.
      errorMethodCount: 8,
      // Longitud máxima de texto antes de hacer quiebres de línea.
      lineLength: 120,
      // Habilitamos el coloreo para leerlo con facilidad.
      colors: true,
      // Permitimos emojis representativos por cada tipo de log.
      printEmojis: true,
    ),
  );

  // Método asíncrono que se encarga de ir a nuestros "assets" y levantar el modelo en memoria RAM.
  Future<void> loadModel() async {
    try {
      // Pedimos a la librería que lea el archivo .tflite y lo pase al intérprete subyacente de C++.
      _interpreter = await Interpreter.fromAsset(
        // Especificamos la ruta exacta a nuestro archivo de red neuronal entrenada.
        'assets/models/mobilenet_v1_1.0_224.tflite',
      );
      // Imprimimos un nivel info confirmando la carga.
      customLogger.i('Modelo cargado exitosamente a nivel nativo');

      // Si el intérprete efectivamente no es nulo...
      if (_interpreter != null) {
        // ...inspeccionamos y extraemos las dimensiones del tensor de entrada (input shape), ej. [1, 224, 224, 3].
        var inputShape = _interpreter!.getInputTensor(0).shape;
        // ...extraemos también la capa de salida final (output shape), por ej. [1, 1001].
        var outputShape = _interpreter!.getOutputTensor(0).shape;
        // Registramos en el log la matriz de entrada requerida.
        customLogger.i('Input shape: $inputShape');
        // Registramos también el tensor resultante esperado.
        customLogger.i('Output shape: $outputShape');
      }
    } catch (e) {
      // En caso de que el archivo del modelo no exista o falle la inicialización.
      customLogger.e('Error cargando el modelo: $e');
      // Es vital lanzar el error para que main.dart lo atrape y lo muestre en la interfaz gráfica.
      throw Exception('Fallo al cargar el modelo TFLite: $e');
    }
  }

  // Método público que permite cerrar las colecciones en memoria asignadas al intérprete tflite para evitar memory leaks.
  void close() {
    // Si el intérprete está instanciado (no es null), cerramos la sesión en C++.
    _interpreter?.close();
    // Registramos que las referencias nativas han sido liberadas exitosamente.
    customLogger.i('Interpreter cerrado');
  }

  // Función asíncrona que toma archivo de imagen y le aplica el modelo matemático, devolviendo probabilidades.
  Future<List<double>> runModel(File imageFile) async {
    // Comprobamos la instancia; si es nulo no podemos trabajar la inferencia.
    if (_interpreter == null) {
      // Registramos el error de estado.
      customLogger.e('El interprete no está inicializado.');
      // Devolvemos lista vacía amigable en vez de crashear el sistema.
      return [];
    }

    // --- 1. Decodificar y redimensionar la imagen a 224x224 ---
    // Leemos bytes crudos del archivo y decodificamos en matriz 2D/3D.
    img.Image? imageInput = img.decodeImage(imageFile.readAsBytesSync())!;
    // Redimensionamos la imagen al ancho/alto demandado por MobileNet (224x224).
    img.Image resizedImage = img.copyResize(
      // Imagen de origen a procesar.
      imageInput,
      // Ancho destino (224 pixeles).
      width: 224,
      // Alto destino (224 pixeles).
      height: 224,
    );

    // --- 2. Preparar el tensor de entrada: [1, 224, 224, 3] ---
    // Creamos una lista moldeada de forma 1 x 224 x 224 x 3 llena de ceros decimales iniciales.
    var input = List.generate(
      // Tamaño total del vector plano: altura x anchura x 3 canales RGB.
      1 * 224 * 224 * 3,
      // Llenado temporal por defecto: 0.0 float32.
      (index) => 0.0,
      // Redoblamos la lista plana para convertirla en matriz multi-dimensional (shape match TFLite).
    ).reshape([1, 224, 224, 3]);

    // --- 3. Extraer RGB y normalizar (escalar de 0-255 a 0.0-1.0) ---
    // Iteramos por las filas 'Y' desde 0 hasta 223.
    for (var y = 0; y < resizedImage.height; y++) {
      // En cada fila, iteramos las columnas 'X' desde 0 hasta 223.
      for (var x = 0; x < resizedImage.width; x++) {
        // Obtenemos el objeto pixel entero en las coordenadas X, Y.
        var pixel = resizedImage.getPixel(x, y);
        // Extraemos Rojo (R) y dividimos por 255.0 para normalizar en decimal.
        var r = pixel.r / 255.0;
        // Extraemos Verde (G) normalizado.
        var g = pixel.g / 255.0;
        // Extraemos Azul (B) normalizado.
        var b = pixel.b / 255.0;

        // Asignamos el canal Rojo [0] al tensor en Y, X.
        input[0][y][x][0] = r;
        // Asignamos el canal Verde [1] al tensor en Y, X.
        input[0][y][x][1] = g;
        // Asignamos el canal Azul [2] al tensor en Y, X.
        input[0][y][x][2] = b;
      }
    }

    // --- 4. Preparar el tensor de salida: [1, 1001] ---
    // Creamos la matriz (pre-formada con ceros) donde TFLite guardará las respuestas a 1001 clases posibles.
    var output = List.filled(1 * 1001, 0.0).reshape([1, 1001]);

    try {
      // --- 5. Ejecutar inferencia ---
      // Inicia el proceso de propagación de la red neuronal. TFLite llena la memoria 'output' desde 'input'.
      _interpreter!.run(input, output);
      // Registramos finalización exitosa en backend log.
      customLogger.i('Inferencia del modelo completada');

      // --- 6. Devolver la lista plana de 1001 probabilidades ---
      // Forzamos el sub-array [0] de resultados a una auténtica List<double> limpia para Flutter.
      return List<double>.from(output[0] as List);
    } catch (e) {
      // Si la capa en C falla (buffers erróneos, etc), capturamos la queja.
      customLogger.e('ERROR durante la inferencia: $e');
      // Retornamos sin crashear la UI.
      return [];
    }
  }
}
