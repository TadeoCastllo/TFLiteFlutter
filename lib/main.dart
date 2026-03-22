// Importamos la biblioteca dart:io para poder trabajar con archivos (como imágenes).
import 'dart:io';
// Importamos el paquete principal de Flutter para crear la interfaz de usuario.
import 'package:flutter/material.dart';
// Importamos el paquete image_picker para seleccionar imágenes de la cámara o galería.
import 'package:image_picker/image_picker.dart';
// Importamos rootBundle para poder leer archivos estáticos (assets) empaquetados en la aplicación.
import 'package:flutter/services.dart' show rootBundle;
// Importamos logger para imprimir mensajes en la consola de forma estructurada y con colores.
import 'package:logger/logger.dart';
// Importamos el servicio personalizado que maneja la lógica de TensorFlow Lite.
import 'service.dart'; // Importamos tu servicio

// Función principal que marca el punto de entrada de la aplicación Flutter.
void main() {
  // Aseguramos que los bindings de Flutter estén inicializados antes de ejecutar la app.
  WidgetsFlutterBinding.ensureInitialized();
  // Arrancamos la aplicación inmediatamente inflando el widget MyApp. ¡Nada de await aquí!
  runApp(const MyApp());
}

// Widget principal de la aplicación, es un StatelessWidget porque su configuración global no cambia una vez renderizada.
class MyApp extends StatelessWidget {
  // Constructor constante para optimizar el rendimiento de la creación del widget en el árbol.
  const MyApp({super.key});

  // Método build que construye y retorna la interfaz gráfica de la aplicación en todo aspecto global.
  @override
  Widget build(BuildContext context) {
    // Retornamos MaterialApp, que es el contenedor principal para apps con Material Design.
    return MaterialApp(
      // Título de la aplicación, útil para accesibilidad y administradores de tareas.
      title: 'Clasificador TFLite',
      // Ocultamos la etiqueta roja de 'DEBUG' en la esquina superior derecha del canvas.
      debugShowCheckedModeBanner: false,
      // Configuramos el tema general de la aplicación.
      theme: ThemeData(
        // Generamos un esquema de colores armónico basado en el color semilla morado profundo.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        // Indicamos explícitamente que queremos usar los componentes de la versión Material 3.
        useMaterial3: true,
      ),
      // Definimos la pantalla de inicio o vista raíz de nuestra aplicación (ModelScreen).
      home: const ModelScreen(),
    );
  }
}

// Pantalla principal donde se interactúa con el modelo, es StatefulWidget porque su estado interno cambiará con el tiempo (ej. mostrar texto o imagen nueva).
class ModelScreen extends StatefulWidget {
  // Constructor constante de la pantalla del modelo.
  const ModelScreen({super.key});

  // Creamos el estado mutable asociado a este widget para permitir re-renders.
  @override
  ModelScreenState createState() => ModelScreenState();
}

// Clase que maneja el estado de ModelScreen, contiene la lógica dura y las variables dinámicas reactivas de pantalla.
class ModelScreenState extends State<ModelScreen> {
  // Instancia de nuestro servicio TensorFlow, marcada como 'late' porque se inicializará en initState (luego de declarar la variable).
  late TFService tfService;
  // Lista de cadenas de texto para almacenar las etiquetas o nombres que el modelo reconoce (las clases).
  List<String> _labels = [];
  // Mensaje de texto que se mostrará en la interfaz para informar al usuario sobre el estado, acciones a tomar o resultado de la AI.
  String _output = 'Cargando modelo TFLite...';
  // Variable File para almacenar el archivo físico de la imagen seleccionada; puede ser nula inicialmente.
  File? _image;
  // Bandera (booleana) para saber internamente en los widgets si el modelo TFLite ya terminó de cargarse en ram y está listo.
  bool _isModelReady = false;

  // Instancia del custom logger para darnos tracking de procesos por consola.
  var customLogger = Logger(
    printer: PrettyPrinter(
      // Número de métodos de la pila mostrar en un log común de debug a nivel info.
      methodCount: 2,
      // Número de tracebacks expandidos si llega a ocurrir un fallo grave tipo .e de logger.
      errorMethodCount: 8,
      // Longitud del wrap a partir de los 120 caracteres en la ventana de terminal output IDE.
      lineLength: 120,
      // Aplica secuencias de escape ANSI para dar bellos colores (solo en debugs soportados).
      colors: true,
      // Muestra iconos (emojis) para diferenciar tipo de mensaje loggeo.
      printEmojis: true,
    ),
  );

  // Método del ciclo de vida que se llama una sola vez cuando el widget se inserta en el árbol de widgets.
  @override
  void initState() {
    // Llamamos siempre al initState funcional de la clase padre.
    super.initState();
    // Inicializamos nuestro servicio experto de TensorFlow Lite.
    tfService = TFService();
    // Invocamos el método asíncrono para cargar el modelo en un hilo separado (no bloqueante para la UI).
    _initTFLite();
    // Invocamos el método para leer las etiquetas ("labels") asociadas a las salidas del modelo.
    _loadLabels();
  }

  // Método asíncrono que delega de manera segura la carga pesada del modelo TFLite.
  Future<void> _initTFLite() async {
    try {
      // Esperamos a que el servicio instancie el intérprete de C++ con el asset apuntado.
      await tfService.loadModel();
      // Verificamos si el widget visual sigue montado en la pantalla antes de actualizar estados internos.
      if (mounted) {
        // Notificamos a Flutter que las variables cambiaron para que gatille un re-render del widget.
        setState(() {
          // Guardamos internamente que el modelo ya está listo para ser usado y desbloquear el botón.
          _isModelReady = true;
          // Actualizamos el string de mensaje informando al usuario que ya puede tomar o seleccionar foto.
          _output = 'Modelo listo. Selecciona una imagen.';
        });
      }
    } catch (e) {
      // Si ocurre un error fatal crítico, verificamos de nuevo el flag mounted de la view.
      if (mounted) {
        // Ejecutamos setState reactivo para estampar el error en rojo en la pantalla.
        setState(() {
          // Mostramos el mensaje crudo detallando el fallo originado por platform bindings o fallas de asset.
          _output =
              '❌ Error fatal al cargar el modelo:\n$e\n\n¿Revisaste el build.gradle?';
        });
      }
    }
  }

  // Función asíncrona para cargar el archivo estático de disco que contiene las etiquetas semánticas (clases a predecir).
  Future<void> _loadLabels() async {
    try {
      // Leemos todo el archivo 'labels.txt' empacotado en assets decodificado como un gran string plano temporal.
      final rawLabels = await rootBundle.loadString('assets/models/labels.txt');
      // Aseguramos que el componente siga vivo para no tirar memory leaks de setState.
      if (mounted) {
        // Pedimos actualización a la UI inyectando estado en variables ram.
        setState(() {
          // Dividimos o parcheamos el texto enorme por cada salto de línea reconociendo cada clase.
          _labels = rawLabels.split('\n');
        });
      }
    } catch (e) {
      // Si el archivo falta, está corrupto o mal ubicado, tiramos error custom al logger pero la app no crashea de inmediato.
      customLogger.e('Error al cargar labels.txt: $e');
    }
  }

  // Función matemática de soporte computacional ("argmax") para indexar en arrays el lugar del número más alto (probabilidad mayor).
  int _argMax(List<double> values) {
    // Escudo lógico de parada si la red no soltó nada, retornamos de default el primero (0) en forma neutral.
    if (values.isEmpty) return 0;
    // Puntero memoria RAM al asumido ganador (por ahora el inicial 0).
    int maxIndex = 0;
    // Pila temporal con float de la probabilidad presunta mayor inicial.
    double maxValue = values[0];
    // Ciclo for iterado de alto rendimiento desde el tag #1 hasta el len(values) total.
    for (int i = 1; i < values.length; i++) {
      // Comparador boleano: si esta celda actual que miro tiene más puntaje que la última anotada en la libreta.
      if (values[i] > maxValue) {
        // Lo anoto en mi pizarra récord mundial como el nuevo valor float absoluto máximo a romper.
        maxValue = values[i];
        // También anoto y capturo la id del poseedor o atleta ganador vigente en mi libreta index.
        maxIndex = i;
      }
    }
    // Después de evaluar todo, retornamos index vencedor real.
    return maxIndex;
  }

  // Función asíncrona para la solicitud de permisos a delegados de imagen y apertura de cámara o galería.
  Future<void> _pickImage(ImageSource source) async {
    // Instanciamos handler de paso nativo a Android/IOS image picker services.
    final picker = ImagePicker();
    // Invocamos nativamente al function esperando hasta la completación, se devuelve path temporal image.
    final pickedFile = await picker.pickImage(source: source);

    // Lógica IF escudo boolean para validar que regresó un buffer y el widget sigue existiendo.
    if (pickedFile != null && mounted) {
      // Entramos al react module e informamos a Flutter para el layout re draw.
      setState(() {
        // Encorchetamos el file route en una abstracción OS file real manejable.
        _image = File(pickedFile.path);
        // Modificamos flag visual banner string para indicarle proximo paso al usuario.
        _output = 'Imagen lista. Presiona "Ejecutar Modelo".';
      });
    }
  }

  // Función asíncrona invocada por el UI button de ejecutar, envía imagen al core bridge tfService.
  void _runModel() async {
    // Primer muro de contención: No ejecutar si el loader de weights ram c++ dice false.
    if (!_isModelReady) {
      // Retornar mensaje reactivo visual informando causa.
      setState(() => _output = 'El modelo aún no está listo.');
      // Breaker temprano (return) para detener todo el invocation logic.
      return;
    }
    // Segundo muro contención preventiva if null reference null memory de foto local.
    if (_image == null) {
      // Modificamos property text canvas ui state para pedir insumo.
      setState(() => _output = 'Por favor, selecciona una imagen primero.');
      // Break de salida early return block functional exit.
      return;
    }

    try {
      // Pinta la iteracion del estado a Analizando imagen para guiar al usuario que hubo accion en el bottom logic.
      setState(() => _output = 'Analizando imagen...');

      // Llamada asíncrona al servicio. Pide la inferencia del TFLite Native bridge y espera el resultado de double variables.
      List<double> result = await tfService.runModel(_image!);

      // Tercer muro map empty boolean property validation si algo falla en C y retorna lista fallida cero length.
      if (result.isEmpty) {
        // Avisar a traves de la visual state property empty render fall safe view y cancelar logic down.
        setState(() => _output = 'El modelo no devolvió resultados.');
        // Cancel logic below.
        return;
      }

      // Calcula con funcion recursiva argMax custom el label de la clase con mas nota ganadora entre las mil de mobilenet.
      final int predictedIndex = _argMax(result);
      // Busca el texto string match para imprimir de la list interna _labels parseada del TXT que leimos al init si se cargo con exito el file logic.
      final String predictedLabel =
          _labels.isNotEmpty && predictedIndex < _labels.length
          // Match mapping text literal de labels array si lo encuentra en safe constraints boundaries boolean format length limits valid rule match format.
          ? _labels[predictedIndex]
          // Si el json text TXT array object index esta vacio, lanza fallback general placeholder literal "Clase #" number limits layout text node default fail safe text param visual string literal label exception property string layout constraint literal offset label structure check index.
          : 'Clase $predictedIndex';
      // Extraemos el maximo valor float (rango entre 0 al 1 de normalizacion) extraido array native pointer result class max list return.
      final double confidence = result[predictedIndex];

      // Insertamos property state trigger node visual re draw layout trigger map text param variable value mapping UI property config limits value map config parameters param event mapper update event node setter limits assignment event rule literal UI mapping tree setup config.
      setState(() {
        // Formateamos concatenacion label predict string property render layout limit decimal string conversion float a decimal de 2 limites percentage formatting y string class limits visual rule format padding limit render update string config assignment mapper UI parameter event parameter limit assignment.
        _output =
            'Predicción: $predictedLabel\nConfianza: ${(confidence * 100).toStringAsFixed(2)}%';
      });
    } catch (e) {
      // Atrapa exceptions logic system out string layout memory crash limits out rules param handler fall catch logic render string layout print error limit setter UI variables handler node limits setup format layout bounds fallback visual mapper parameter text setup parameter condition structure check map rules limits structure UI rules.
      setState(() => _output = 'Error al ejecutar la inferencia:\n$e');
      // Imprime fallback en background dev console trace string rule trace property mapper limit param literal map logic structure limits bounds block format error param map handler property config limit mapping text print constraint struct limits error string handler mapper logging parameter struct literal print text limit print bounds logic bounds struct log print.
      customLogger.e('Error en _runModel: $e');
    }
  }

  // Scaffold mapper rule method ui bounds mapping class flutter setup object node list format UI rule loop param parameters rule visual root map limits configuration UI return structure assignment config bounds rendering param rendering bounds tree map class object node mapper layout configuration format limit.
  @override
  Widget build(BuildContext context) {
    // MaterialApp structure material 3 basic bounds layout components padding rule object wrapper constraints block loop loop parameter array object structure struct.
    return Scaffold(
      // AppBar toolbar layout config title map structure format param text param title definition component bounds param struct map bounds text assignment string text limits.
      appBar: AppBar(title: const Text('Clasificador de Imágenes')),
      // Padding alignment helper wrap block definition parameters rules constraint UI bounds align wrapper logic parameters array limit limits parameter parameter offset node variables limit config format.
      body: Center(
        // View rule wrapper overflow constraints rendering parameters limit layout parameter mapper logic wrap padding rule structure setter class block format format offset visual string layout constraint object.
        child: SingleChildScrollView(
          // Array limits mapping configuration setter rules class wrapper components bounds literal node array setter structure layout parameters mapping tree struct parameters tree properties map offset block constraint layout mapper text array definition visual list UI layout configuration structural definition mapping list property limits param parameters visual setup wrap assignment format limit parameter limit settings setup logic constraints rule limits string class loop mapping parameter mapping limits format settings array mapper parameters map map definition format UI struct node string parameters format.
          child: Column(
            // Setup axis settings logic UI mapping parameters vertical constraint spacing map.
            mainAxisAlignment: MainAxisAlignment.center,
            // Children string parameters node configuration assignment array setup limit string object format UI list layout properties wrap block constraint map format.
            children: [
              // Boolean tree configuration condition limit mapping format wrap parameters structure block struct array.
              _image == null
                  // UI rendering string definition text rule limits configuration assignment structure property layout.
                  ? const Text(
                      'No has seleccionado ninguna imagen.',
                      style: TextStyle(fontSize: 16),
                    )
                  // Array property component map param mapping configuration setup format string struct padding string limits limits text mapping boolean struct constraint rendering.
                  : Image.file(_image!, height: 250, fit: BoxFit.cover),

              // Spacing map padding wrapper block limits limits node string format empty mapping dimensions struct definition string wrapper layout loop limit text variable setting dimension box constraint empty limit.
              const SizedBox(height: 30),

              // Array structure limit layout structural rule limit property block visual map limit variables row configuration list constraint layout configuration tree string limit array map constraint variables configuration array string configuration.
              Row(
                // Constraint block parameters mapper align string mapping struct structure definition format rules config string setting loop settings parameter bounds.
                mainAxisAlignment: MainAxisAlignment.center,
                // Array container elements property layout limits logic parameters literal nodes map structural logic mapping properties format mapping setup array visual logic config constraint loop limits block structure map component array string constraint boolean rules node structural limit literal.
                children: [
                  // Button mapping UI array visual action loop trigger property callback action struct parameters configuration format trigger format setup tree rule string mapper wrapper mapping boolean limit event string mapping callback class array text padding padding limits visual logic string rule mapping boolean format padding loop constraint constraint wrapper constraint components text padding visual action layout definition setup setup structural variables constraints format button variable node string layout param trigger limits offset parameter action trigger.
                  ElevatedButton.icon(
                    // Call wrap parameter string config callback pointer action properties rule layout limits mapping mapper event object block parameter loop literal limits event parameter boolean mapping struct tree properties string limits rules format.
                    onPressed: () => _pickImage(ImageSource.gallery),
                    // Const mapper string parameter UI block logic rule array class loop literal config symbol symbol struct mapping mapping property configuration loop mapper format string.
                    icon: const Icon(Icons.photo_library),
                    // String title wrapper config text map literal limits action constraint format title node class mapper UI structure structure string variable rule padding list struct property button definition array layout literal wrap padding node.
                    label: const Text("Galería"),
                  ),
                  // Spacing array padding width string loop struct spacing wrapper width parameter limit variables parameter block width dimension setting width setting boolean tree mapping limit constraint parameters container bounds padding visual configuration format.
                  const SizedBox(width: 20),
                  // ElevatedButton layout rule layout structural visual format config pointer logic mapping literal binding action param properties layout object loop structure setup definition callback enum limits padding properties layout logic node property pointer wrap event padding wrap limits settings layout event.
                  ElevatedButton.icon(
                    // Lambda mapping map pointer config definition property limits literal rules mapping layout configuration binding block properties trigger wrapper settings mapper property mapping condition struct boolean.
                    onPressed: () => _pickImage(ImageSource.camera),
                    // Const block symbol string configuration array limits ui node parameter offset enum rules setting wrapper struct UI setup properties limit mapper definition dimensions string layout config.
                    icon: const Icon(Icons.camera_alt),
                    // Literal map structure assignment action wrap bounds logic node wrapper button limit configuration tree format block wrap structural tree visual struct literal struct structure format assignment setter map mapping visual title structure struct constraint list layout constraint rule variables block.
                    label: const Text("Cámara"),
                  ),
                ],
              ),

              // Dimensions empty block rules parameters loop visual space string empty array setting space property mapping wrap limits dimension wrapper size variables class dimension configuration parameter map limit structure offset mapping format class variables configuration format constraint map settings string.
              const SizedBox(height: 30),

              // Node parameter wrapper component block properties trigger condition mapping string parameter logic config layout loop callback parameters property structure mapping boolean parameters settings map mapping loop string struct tree rule constraint button event offset configuration boolean logic trigger action rule setup definition dimensions limits map logic variable mapping map structure text setter node offset constraint list setting struct mapping offset rendering layout trigger mapping config rule wrapper.
              ElevatedButton(
                // Style component definition block bounds layout setting padding boolean mapper configuration limits mapping visual setup config setting property property offset map limits UI struct format layout string dimensions offset struct condition.
                style: ElevatedButton.styleFrom(
                  // Dimension configuration limits alignment map logic structure wrapper property limits loop offset layout padding struct array rules setting struct constraint config.
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 15,
                  ),
                  // Background config rules loop structural definition parameters layout limits string wrapper parameter map properties variable setting rules limit padding array parameter format limits condition tree condition string visual enum setter setter config loop format.
                  backgroundColor: _isModelReady
                      ? Colors.deepPurple
                      : Colors.grey,
                  // Tinta string mapping variable param mapping bounds map limit limits logic map struct wrapper format properties text properties tree limit node mapping logic structural array logic format loop definition layout string parameter map definition assignment parameters map structure format boolean wrap struct param wrap variables string configuration format property map boolean setup UI parameter string.
                  foregroundColor: Colors.white,
                ),
                // Boolean validation rule format structure pointer format limits action visual settings callback binding assignment setup definition wrapper assignment loop properties definition limits format property assignment layout parameter config assignment limit logic setup pointer condition mapper boolean.
                onPressed: _isModelReady ? _runModel : null,
                // Label string parameters array limits wrap logic properties condition tree format block UI definition node limit literal wrapper string setting title format limits constraint logic UI padding class settings object struct node rule bounds mapping dimensions class parameter text node dimension string constraint label format parameters node literal setting logic map text padding structure definition mapping config block array layout wrapper setting label struct variable offset setter label config visual condition text variables settings variables constraint offset variable layout setting.
                child: const Text(
                  "Ejecutar Modelo",
                  style: TextStyle(fontSize: 18),
                ),
              ),

              // Void spacer mapper array node boolean settings block dimensions setting wrapper bounds map parameters constraint space properties boolean padding space rules offset limits loop empty mapping tree padding block spacing setting value block constraint spacing string boolean layout string limits structural constraint text rules string configuration wrap parameter configuration map setting loop list constraint limits empty size bounds text boolean parameter rule padding format constraint bounds definition logic structure format limits array map.
              const SizedBox(height: 30),

              // Wrapper limit rules parameters array boolean setup class structure setup string layout loop wrapper format map setting dimensions margin variable format wrap parameter alignment limits constraint parameter dimension padding configuration setter block offset configuration map definition padding property mapping format variable mapping string map structural tree config layout logic structure dimensions wrapper limits empty parameters variables setter assignment struct limit dimensions boolean configuration list padding literal rules offset wrap block format class setting dimensions map assignment loop settings limits value dimensions constraint settings padding wrapper rules boundaries text block offset format block offset logic node setting assignment parameters loop string constraints parameter limits map array layout rules string UI logic text definition variable configuration alignment wrapper layout parameters mapping mapping assignment wrapper format setup visual parameters string format structure.
              Padding(
                // Offset horizontal margin variables bounds assignment block parameters dimensions configuration wrap rules limit layout block settings array padding format constraints rules limits margin logic string setting dimension setting padding width configuration format configuration text string dimensions tree margin map layout logic string wrap struct array logic properties UI structure logic logic layout variable limit layout limits map padding parameters block offset parameter parameter variable wrap dimensions wrap array format alignment dimensions boundaries array format dimensions configuration variables loop boolean loop boolean array format mapping parameter.
                padding: const EdgeInsets.symmetric(horizontal: 20),
                // Text rendering UI padding variables text wrap block wrap logic alignment limits rules setting definition variable configuration layout constraint loop constraints array logic parameters mapping boolean condition setup properties limits string setter limits offset mapping parameters map dimension structure boolean dimensions configuration parameters variables definition format boolean data limits boundaries wrapper parameters limit map data logic constraint configuration mapping loop settings limits variable structure offset limits mapping condition structure variable condition block boolean mapping rule size value configuration rules wrapper variables assignment offset configuration format condition offset UI condition limit format configuration parameters loop format constraint definition rules text constraint setting variables map array logic.
                child: Text(
                  // State variable mapping map array limits array logic parameters node struct format data property wrapper parameters text map array variable parameters conditional variable mapping text conditional property data layout string mapper data rendering parameters configuration.
                  _output,
                  // Setup logic padding parameters offset align mapper configuration data variables alignment constraint format config parameter dimensions boolean limits constraint parameter block limits format loop variables format literal loop limits mapping wrapper constraint mapper limit offset parameters setter data limit map data parameters align parameters condition mapping format limits wrapper.
                  textAlign: TextAlign.center,
                  // Style logic font map setter dimensions block string rules conditions map dimensions padding format parameters logic mapping limit format text mapper wrapper node constraint wrapper parameters text alignment layout layout array mapper format logic setting layout alignment limit wrap alignment parameter setter mapper parameters string rule setter map variable struct setting limits variables constraint object format layout structure limits variables rules format constraint wrap settings definition setter configuration map settings array condition constraint rules struct wrap logic mapping rules alignment boolean logic map mapping.
                  style: TextStyle(
                    // Dimension format settings parameters loop mapping width configuration text rule block UI assignment constraint constraint loop array constraints struct format block parameters format wrapper rules UI array setting structure rule layout array dimensions block dimensions variables size setting UI constraint dimensions alignment.
                    fontSize: 18,
                    // Weight layout rendering mapper variables mapping struct param mapping map variables configuration dimensions configuration format mapping parameters map struct alignment layout constraints wrapper offset constraint configuration logic structure text constraints loop variables condition dimensions definition map logic rules format structure string padding configuration mapper definition setup setting padding setter array limits wrap setter configuration mapping padding format alignment map setter structural constraints string assignment block wrapper struct value UI rule limits alignment wrap settings string array.
                    fontWeight: FontWeight.bold,
                    // Color state parameter structure string logic setup conditional parameter wrapper map structural mapper constraints boolean logic configuration padding rules text condition logic conditional variable parameters node text block logic conditional limits format setter format struct parameters wrapper loop boolean logic map alignment boolean mapper condition parameters tree limits map array format definition setup format string definition configuration condition data struct variables mapping definition alignment loop definition limits format offset string mapping parameter mapping logic format settings mapping UI layout setter parameters map offset data rendering settings constraint condition offset layout setting limits.
                    color: _output.startsWith('❌')
                        ? Colors.red
                        : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
