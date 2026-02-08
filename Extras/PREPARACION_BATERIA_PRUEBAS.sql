/*COMENCEMOS, LAS FASES SERIAN,  ESTO ES SIMULANDO QUE EL SISTEMA TENDRA AUTOMATIZACIONES POR TIEMPO PERO TAMBIEN CORRECION MANUAL POR PARTE DE UN ADMIN O COORDINADOR.

NO SE TE OLVIDE  USAR LOS SP PARA GENERAR LAS TARJETAS DEL DASHBOARD Y VER QUE REALMENTE SE ESTAN APLICANDO LOS CALCULOS CORRESPONDIENTES 
Y ACTUALIZANDO CONFORME SE USA EL SISTEMA, ESTO PORQUE DESPUES SI PASAN TODAS ESTAS PRUEBAS Y VALIDACIONES QUE TIENE CADA SP CONSTRUIREMOS LOS QUE SE USARAN PARA 
LAS GRAFICAS Y REPORTES.
al final de todo te pasare que validaciones debemos de hacer para cada caso tambien.


-- ================================================================================
-- CONFIGURACIÓN INICIAL DE ACTORES Y VARIABLES GLOBALES
-- ================================================================================

SET @IdAdminMaestro = 322;  -- Tu Super Admin existente en el sistema
SET @FechaActual = CURDATE();

-- ================================================================================
-- FASE 0: LIMPIEZA PREVENTIVA (DATA STERILIZATION)
-- ================================================================================

  =================================================================================
   FASE 1: CONSTRUCCIÓN DE INFRAESTRUCTURA COMPLETA
   =================================================================================
   Creamos todo el ecosistema necesario para simular un ambiente de producción:
   - Geografía completa (País → Estado → Municipio)
   - Organización completa (Dirección → Subdirección → Gerencia)
   - Catálogos RH (Región, Régimen, Puesto, Rol)
   - Infraestructura física (Centro de Trabajo, Departamento, Sedes)
   - Catálogos académicos (Tipos de Instrucción, Temas, Modalidades)
   - Catálogos de estatus (Capacitación y Participante)
   =================================================================================  

 =================================================================================
   FASE 2: CREACIÓN DE ACTORES (USUARIOS DEL SISTEMA)
   =================================================================================
   Creamos los 14 usuarios necesarios para la simulación:
   - 2 Administradores
   - 2 Coordinadores
   - 3 Instructores 
   - 25 Participantes
   ================================================================================  

 =================================================================================
   FASE 3: CREACIÓN DE LAS 5 CAPACITACIONES EN ESTADO "PROGRAMADO"
   =================================================================================
   Las capacitaciones nacen en estado PROGRAMADO.
   Este es el punto de partida del ciclo de vida.
   NOTA: Usamos SP_RegistrarCapacitacion que crea Cabecera + Detalle atómicamente.
   =================================================================================  

 =================================================================================
   FASE 4: INSCRIPCIÓN DE PARTICIPANTES EN LAS CAPACITACIONES.
   =================================================================================
   Los participantes se inscriben a los cursos.
   NOTA: Este paso NO cambia el estatus de la capacitación (sigue en PROGRAMADO).
EN ESTE PASO SE USARA EL SP_RegistrarParticipanteCapacitacion (ESTE LO REGISTRA UN ADMIN O COORDINADOR) Y EL SP_RegistrarParticipanteCapacitacion (ESTE ES EL USUARIO PROPIO QUE SE ENTERO DE LA CAPACITACION Y SE POSTULO.)
   =================================================================================  

 =================================================================================
   FASE 5: AUTORIZACIÓN DE CAPACITACIONES (PROGRAMADO → POR INICIAR)
   =================================================================================
   OBJETIVO:
   Simular la autorización formal por parte del Coordinador.
   MÉTODO FORENSE:
   Utilizamos `SP_Editar_Capacitacion` para cambiar el estatus. Esto genera una
   "Versión 2" del curso (la versión Autorizada), dejando la "Versión 1" (Borrador)
   en el historial como evidencia del plan original.
 =================================================================================  

 =================================================================================
   FASE 6: ESCENARIOS DE CAMBIOS Y REPROGRAMACIÓN (GENERACIÓN DE HISTORIAL)
   =================================================================================
   Aquí simulamos los imprevistos que generan cambios en las capacitaciones.
   CAPACITACIÓN 1: NO HAY CAMBIOS (flujo perfecto)
   CAPACITACIÓN 2: Cambio de instructor + Reprogramación de fecha
   CAPACITACIÓN 3: Cambio de sede + Cambio de modalidad
   Los cambios generan:
   - Cambio de estatus a REPROGRAMADO
   - Registro en historial de cambios
   
   Usamos SP_Editar_Capacitacion que:
   - Crea una NUEVA versión (DatosCapacitaciones) con los cambios
   - Archiva la versión anterior (Activo = 0)
   - Migra automáticamente los participantes a la nueva versión
   - Genera historial de cambios auditable
   
   EN ESTA PARTE YA UNA VES CARGADOS LOS ALUMNOS DEBEMOS PODER HACERLE CAMBIOS A LA PLANEACION ORIGINAL, 
   RECUERDA QUE CONCIDERAMOS QUE LOS ALUMNOS PUEDEN HABER X NUMERO EN EL SISTEMA Y LOS DE LA LISTA REAL QUE CONSIDERAN A LOS QUE NO ESTAN AUN REGISRADOS EN EL SISTEMA.
   AUN LOS ALUMNOS NO CAMBIAN DE ESTATUS ESTARAN EN EL INICIAL, PERO HABRA ALGUNOS CASOS DE LOS QUE SUPONGAMOS QUE ALGUNOS ALUMNOS SE REGISTRARON PERO AL FINAL PIDIERON SU BAJA
   DE ESA CAPACITACION ELLOS CAMBIARAN AL ESTATUS DE PARTICIPANTES BAJA PARA QUE NO LOS CUENTE EL SITEMA AL MOMENTO DE TRATAR DE LIBERAR ESE ESPACIO. CUANDO SE DEN DE BAJA 
   DEBEMOS SIMULAR QUE OTRA PERSONA QUIERE LLEVAR ESA CAPACITACION Y OCUPAR EL LUGAR DE ESA PARSONA, Y OTROS CASOS DE QUE SE DIO DE BAJA PERO FUE POR UN ERROR DEL COORDINADOR O ADMIN
   Y DEBE REINTEGRARLO ANTES QUE EL SISTEMA NO SE LO PERMITA, ES DECIR LA LOGICA SERA LA DE UNA FILA DE ACCESO, SI TE VAS PIERDES TU LUGAR Y TIENE QUE VOLVER A FORMARTE SI QUIERES
   INTEGRARTE DE NUEVO Y ESPERAR A VER SI ALCANZAS A ENTRAR ANTES QUE SE LLENE EL CUPO, Y SI SE VA ALGUIEN Y NO VUELVE EL QUE ESTABA DETRAS DE EL AVANZA HASTA QUE SE LLENE EL CUPO..
   =================================================================================  
   
    =================================================================================
   FASE 7: EJECUCIÓN DE CAPACITACIONES (POR INICIAR → EN CURSO) - VERSIÓN FORENSE
   =================================================================================
   OBJETIVO:
   Simular el arranque operativo de los cursos.
   MÉTODO:
   1. Usamos SP_Editar para cambiar el estatus del CURSO a "EN CURSO".
      Esto genera una nueva versión histórica (evidencia de inicio).
   2. Actualizamos la asistencia de los participantes vinculados a esta NUEVA versión.
   EN ESTA PARTE SE DEBE HACER TAMBIEN SIMULANDO UN CAMBIO AUTOMATICO DE QUE CUANDO EL CURSO CAMBIA AUTOMATICAMENTE A EN CURSO,
   LOS ALUMNOS REGISTRADOS EN ESTA TAMBIEN AVANZAN A LA SIGUIENTE PORQUE SIGNIFICA QUE EL CURSO SE ESTA LLEVANDO A CABO YA SIN NINGUN CAMBIO,
   PARA ESO USARA EL SP_EDITARPARTICIPANTECAPACITACION SOLO COMO SIMULAR LO QUE HARA EL SITEMA.
   =================================================================================  
   
    =================================================================================
   FASE 8: FINALIZACIÓN Y PERÍODO DE EVALUACIÓN (EN CURSO → EVALUACIÓN)
   =================================================================================
   OBJETIVO:
   Cerrar la etapa de ejecución y abrir la etapa administrativa de evaluación.
   MÉTODO FORENSE:
   1. Usamos SP_Editar para cambiar el estatus a "EVALUACIÓN".
   2. Esto confirma la fecha y hora exacta en que el instructor terminó de impartir.
   3. Registramos las calificaciones sobre esta NUEVA versión vigente.
   
   EN ESTA PARTE EL SIMULAREMOS QUE EL ALUMNO AUN NO SE CAMBIARA SU ESTATUS HASTA QUE SUBAN:
   SU CALIFICACION Y ASISTENCIA ALGUNO DE ESTOS ROLES UN INSTRUCTOR, COORDINADOR O UN ADMIN,
   UNA VES SUBIDA LA CALIFICACION EL ESTATUS DE LOS ALUMNOS DEBERA CAMBIAR CONFORME SI SU CALIFICACION ES MAYOR A EL 70 EL ESTATUS DE APROBADO,
   PERO SI SU CALIFICACION ES MENOR A ESO TENDRA EL ESTATUS DE NO APROBADO, ESTO YA LO HACE EL SP AUTOMATICAMENTE ASI QUE SOLO TE TOCARA EJECUTARLO.
   =================================================================================  
   
    =================================================================================
   FASE 9: DETERMINACIÓN DE ACREDITACIÓN (EVALUACIÓN → ACREDITADO/NO ACREDITADO)
   =================================================================================
   OBJETIVO:
   Oficializar el resultado del curso mediante un dictamen administrativo.
   MÉTODO FORENSE:
   Usamos SP_Editar para cambiar el estatus a ACREDITADO o NO ACREDITADO.
   Esto sella el expediente académico con una nueva versión histórica firmada por el Coordinador.
   
   ESTA FASE A  DIFERENCIA DE LA ANTERIOR ES APLICADA A LA CAPACITACION ESTA OCURRE UNA VES QUE TODOS LOS ALUMNOS 
   ESTEN EVALUADOS ES DECIR TENGAN ASISTECIA Y PARTICIPACION, LO QUE HARAS ES SIMULAR IN CAMBIO DE ESTATUS AUTOMATICO LA CAPACITACION
   DEJARA DE ESTAR EN EL ESTATUS DE EN EVALUACION Y PASARA A EL ESTATUS DE APROBADO O NO  APROBADO ESTO DEPENDIENDO SI EL 70% DE LOS
   ALUMNOS APROBARON O NO ES DECIR SI EXISTEN 30 CUPOS EN EL SISTEMA Y SOLO INSCRITOS HAY 17 Y POR FUERA EL RESTO, ESOS 17 DEBRAN ESTAR EN ALGUNO DE ESOS 2 ESTADOS
   Y HARA ESTADISCTA PARA DECIR QUE ESTATUS DEBERA TENER LA CAPACITACION  PORQUE SI MENOS DEL 70% DE LOS ALUMNOS ISNCITOS EN EL SISTEMA EN ESA CAPACITACION ESTAN APROBADO
   DEBERAN REUNIRSE EL COORDINADOR CONN EL INSTRUCTOR DE ESTA CAPACITACION PARA SABER PORQUE ES UN ESTATUS DE ADMINISTRATIVOS SOLAMENTE PARA QUE SEPAN EL PORQUE PASO ESO.
   ================================================================================= 
   
    =================================================================================
   FASE 10: CIERRE DE CAPACITACIONES (ACREDITADO/NO ACREDITADO → FINALIZADO)
   =================================================================================
   OBJETIVO:
   Simular el cierre administrativo por parte del Coordinador.
   MÉTODO FORENSE:
   En lugar de un UPDATE directo, usamos `SP_Editar_Capacitacion`.
   Esto crea una nueva versión en el historial con el estatus 'FINALIZADO',
   firmada por el Coordinador, preservando la versión de 'EVALUACIÓN' como evidencia previa.
   
   AQUI SIMULAREMOS QUE YA PASO TIEMPO QUE LLEVABA EN ALGUNO DE LOS OTROS 2 ESTADOS (APROBADO / NO APROBDO) LA CAPACITACION
   AL REDEDOR DE 3 SEMANAS. EL SISTEMA AVANZARA AUTOMATICAMENTE LA CAPACITACION A EL ESTATUS DE FINALIZADO.  Y TAMBIEN 
   A LOS ALUMNOS NO SE LES AVANZARA A EL SIGUIENTE ESTADO PORQUE LOS ESTADOS APRROBADO Y NO APROBADO SON EL FINAL DE SU CICLO DE VIDA EN ESA CAPACITACION.
   =================================================================================  
   
    =================================================================================
   FASE 11: ARCHIVADO DE CAPACITACIONES (FINALIZADO → ARCHIVADO)
   =================================================================================
   El coordinador archiva las capacitaciones para evitar ediciones futuras.
   O el sistema las archiva automáticamente después de 3 meses.
   NOTA: SP_CambiarEstatusCapacitacion solo permite archivar si el estatus
   tiene Es_Final = 1 (FINALIZADO, ARCHIVADO, CANCELADO).
   
   POR ULTIMO YA UNA VES QUE HAYA CONCLUIDO LA CAPACITACION EL COORDINADOR O ADMIN  PODRA ARCHIVAR LA CAPACITACION
   PARA ASI QUE DEJE DE APARECERLES EN LAS VISTAS PARA UNIRSE A LOS ALUMNOS, Y EVITAR QUE SE INSCRIBAN EN UNA CAPACITACION QUE YA SE LLEVO A CABO
   =================================================================================  
   
    =================================================================================
   FASE 12: PRUEBA DE ESCENARIO DE CANCELACIÓN (CORREGIDO)
   =================================================================================
   Objetivo: Validar que el flujo de cancelación respete la integridad transaccional.
   Estrategia:
     1. Registrar curso normal (PROGRAMADO) usando SP oficial.
     2. Cancelar curso (CANCELADO) usando SP de Edición para generar historial.
     3. Archivar (ARCHIVADO) simulando paso del tiempo.
     
     AQUI VALIDAREMOS NUEVAMENTE VACIOS ESCENARIOS
     EL PRIMERO SERA CANCELAR UN CURSO QUE AUN NO HAYA SIDO LLEVADO A CABO Y  NO TENGA ALUMNOS.
     EL SEGUNDO CANCELAR UN CURSO CANCELAR UN CURSO QUE TIENE ANUMNOS PERO NO SE HA LLEVADO A CABO.
   =================================================================================  
   
    =================================================================================
   FASE 13: PRUEBAS DE ESTRÉS Y SEGURIDAD DE ELIMINACIÓN (HARD DELETE CHECKS)
   =================================================================================
   OBJETIVO:
   Certificar que las 4 capas de seguridad del SP_EliminarCapacitacion funcionan.
   No queremos borrar nada todavía; queremos ver que el sistema SE NIEGUE a borrar
   cuando las condiciones no son seguras.
   =================================================================================  
   
    =================================================================================
   FASE 14: LIMPIEZA FINAL (TEARDOWN) VÍA SPs OFICIALES
   =================================================================================
   OBJETIVO:
   Desmontar el escenario de pruebas utilizando EXCLUSIVAMENTE los Procedimientos Almacenados
   del sistema. Esto valida que la lógica de "Hard Delete" funciona correctamente cuando
   se cumplen las precondiciones (ej: borrar hijos primero).
   =================================================================================  
   
    VALIDACIONES POR REALIZAR															
   
   PARA LA REGISTRAR CAPACITACIONES:
   
   
     ============================================================================================
       BLOQUE 2: CAPA DE SANITIZACIÓN Y VALIDACIÓN SINTÁCTICA (FAIL FAST)
       Validación de tipos de datos, nulidad y reglas aritméticas básicas.
       Si algo falla aquí, se aborta ANTES de realizar cualquier lectura costosa a la base de datos.
       ============================================================================================ 
    
    -- 2.0 Limpieza de Strings
    -- Aplicamos TRIM para eliminar espacios accidentales. NULLIF convierte '' en NULL real.
    SET _Numero_Capacitacion = NULLIF(TRIM(_Numero_Capacitacion), '');
    SET _Observaciones       = NULLIF(TRIM(_Observaciones), '');

    -- 2.1 Validación de Obligatoriedad: FOLIO
    IF _Numero_Capacitacion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: El Folio es obligatorio y no puede estar vacío.';
    END IF;

    -- 2.2 Validación de Obligatoriedad: SELECTORES (Dropdowns)
    -- Los IDs deben ser números positivos. Un valor <= 0 indica una selección inválida o "Seleccione...".
    
    IF _Id_Gerencia IS NULL OR _Id_Gerencia <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar una Gerencia válida.';
    END IF;

    IF _Id_Tema IS NULL OR _Id_Tema <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar un Tema válido.';
    END IF;

    -- 2.3 Validación de Negocio: RENTABILIDAD (Cupo Mínimo)
    -- Regla de Negocio: No es viable abrir un grupo para menos de 5 personas.
    IF _Cupo_Programado IS NULL OR _Cupo_Programado < 5 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [400]: El Cupo Programado debe ser mínimo de 5 asistentes.';
    END IF;

    -- 2.4 Validación de Obligatoriedad: INSTRUCTOR
    IF _Id_Instructor IS NULL OR _Id_Instructor <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar un Instructor válido.';
    END IF;

    -- 2.5 Validación de Negocio: COHERENCIA TEMPORAL (Fechas)
    -- Regla 1: Ambas fechas son obligatorias.
    IF _Fecha_Inicio IS NULL OR _Fecha_Fin IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Las fechas de Inicio y Fin son obligatorias.';
    END IF;

    -- Regla 2: El tiempo es lineal. El inicio no puede ocurrir después del fin.
    IF _Fecha_Inicio > _Fecha_Fin THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: La Fecha de Inicio no puede ser posterior a la Fecha de Fin.';
    END IF;

    -- 2.6 Validación de Obligatoriedad: LOGÍSTICA (Sede, Modalidad, Estatus)
    IF _Id_Sede IS NULL OR _Id_Sede <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar una Sede válida.';
    END IF;

    IF _Id_Modalidad IS NULL OR _Id_Modalidad <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar una Modalidad válida.';
    END IF;

    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE ENTRADA [400]: Debe seleccionar un Estatus válido.';
    END IF;

     ============================================================================================
       BLOQUE 3: CAPA DE VALIDACIÓN DE EXISTENCIA (ANTI-ZOMBIE RESOURCES)
       Objetivo: Asegurar la Integridad Referencial Operativa.
       Verificamos contra la BD que los IDs proporcionados no solo existan, sino que estén VIVOS (Activo=1).
       ============================================================================================ 

    -- 3.1 Verificación Anti-Zombie: GERENCIA
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Gerencias_Activos` WHERE `Id_CatGeren` = _Id_Gerencia LIMIT 1;
    
    IF v_Es_Activo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [404]: La Gerencia seleccionada no existe en la base de datos.';
    END IF;
    IF v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: La Gerencia seleccionada está dada de baja (Inactiva).';
    END IF;

    -- 3.2 Verificación Anti-Zombie: TEMA
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Temas_Capacitacion` WHERE `Id_Cat_TemasCap` = _Id_Tema LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: El Tema seleccionado no existe o está inactivo.';
    END IF;

    -- 3.3 Verificación Anti-Zombie: INSTRUCTOR
    -- Nota: Validamos tanto la existencia del Usuario como la vigencia de su Info Personal.
    SET v_Es_Activo = NULL;
    SELECT U.Activo INTO v_Es_Activo 
    FROM Usuarios U 
    INNER JOIN Info_Personal I ON U.Fk_Id_InfoPersonal = I.Id_InfoPersonal
    WHERE U.Id_Usuario = _Id_Instructor AND I.Activo = 1 
    LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: El Instructor seleccionado no está activo o su cuenta ha sido suspendida.';
    END IF;

    -- 3.4 Verificación Anti-Zombie: SEDE
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Cases_Sedes` WHERE `Id_CatCases_Sedes` = _Id_Sede LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: La Sede seleccionada no existe o está cerrada.';
    END IF;

    -- 3.5 Verificación Anti-Zombie: MODALIDAD
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = _Id_Modalidad LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: La Modalidad seleccionada no es válida o está inactiva.';
    END IF;

    -- 3.6 Verificación Anti-Zombie: ESTATUS
    SET v_Es_Activo = NULL;
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = _Id_Estatus LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: El Estatus seleccionado no es válido o está inactivo.';
    END IF;
    
    
     --------------------------------------------------------------------------------------------
       PASO 4.1: BLINDAJE DE IDENTIDAD (BLOQUEO PESIMISTA)
       Verificamos la unicidad del Folio usando `FOR UPDATE`.
       Esto bloquea el índice del folio si ya existe, obligando a otras transacciones a esperar.
       Evita condiciones de carrera en la verificación de duplicados.
       -------------------------------------------------------------------------------------------- 
    SELECT `Numero_Capacitacion` INTO v_Folio_Existente
    FROM `Capacitaciones`
    WHERE `Numero_Capacitacion` = _Numero_Capacitacion
    LIMIT 1
    FOR UPDATE;

    IF v_Folio_Existente IS NOT NULL THEN
        ROLLBACK; -- Liberamos el bloqueo inmediatamente antes de salir.
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE IDENTIDAD [409]: El FOLIO ingresado YA EXISTE en el sistema. No se permiten duplicados.';
    END IF;

     Verificación Inmediata de Concurrencia post-INSERT 
     Si el Handler 1062 se disparó durante el insert anterior, abortamos. 
    IF v_Dup = 1 THEN 
        ROLLBACK; 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE CONCURRENCIA [409]: El Folio fue registrado por otro usuario hace un instante. Por favor verifique.'; 
    END IF;
    
         Validación Final de Integridad de la Transacción Compuesta 
     Si falló el insert del hijo (ej: FK rota no detectada), revertimos el padre. 
    IF v_Dup = 1 THEN 
        ROLLBACK; 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [500]: Fallo crítico en la creación del detalle operativo. Transacción revertida para mantener consistencia.'; 
    END IF;

     ============================================================================================
       BLOQUE 5: COMMIT Y RESPUESTA (FINALIZACIÓN EXITOSA)
       Si llegamos aquí, todo es perfecto. Confirmamos los cambios en disco y notificamos.
       ============================================================================================ 
    COMMIT;

    SELECT 
        'ÉXITO: Capacitación registrada correctamente.' AS Mensaje,
        'CREADA' AS Accion,
        v_Id_Capacitacion_Generado AS Id_Capacitacion, -- ID Interno para uso del Backend.
        _Numero_Capacitacion AS Folio;                 -- ID de Negocio para mostrar al Usuario.
        
PARA EL SP_ObtenerMatrizPICADE VALIDAR:

     ============================================================================================
       FASE 0: PROGRAMACIÓN DEFENSIVA (DEFENSIVE CODING BLOCK)
       Objetivo: Validar la coherencia de la petición antes de consumir recursos del servidor.
       ============================================================================================ 
    
     0.1 Integridad de Parametrización 
     Regla: El motor de reportes no puede adivinar fechas. Deben ser explícitas. 
    IF _Fecha_Min IS NULL OR _Fecha_Max IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Las fechas de inicio y fin son obligatorias para delimitar el reporte.';
    END IF;

     0.2 Coherencia Temporal (Anti-Paradoja) 
     Regla: El tiempo es lineal. El inicio no puede ocurrir después del fin. 
    IF _Fecha_Min > _Fecha_Max THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: Rango de fechas inválido. La fecha de inicio es posterior a la fecha de fin.';
    END IF;


PARA VALIDAR SP_BuscadorGlobalPICADE:

  ============================================================================================
       FASE 0: PROGRAMACIÓN DEFENSIVA (DEFENSIVE CODING BLOCK)
       Propósito: Proteger al servidor de consultas costosas o vacías.
       ============================================================================================ 
    IF LENGTH(_TerminoBusqueda) < 3 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ADVERTENCIA DE SEGURIDAD [400]: El término de búsqueda debe tener al menos 3 caracteres.';
    END IF;

   PARA VALIDAR EL SP_Dashboard_ResumenGerencial:
   
    ============================================================================================
   FASE 0: PROGRAMACIÓN DEFENSIVA
   ============================================================================================ 
   
	-- Validación 1: Campos obligatorios
	IF _Fecha_Min IS NULL OR _Fecha_Max IS NULL THEN
		SIGNAL SQLSTATE '45000' 
		SET MESSAGE_TEXT = 'ERROR [400]: Se requiere un rango de fechas para calcular el resumen gerencial.';
	END IF;

	-- Validación 2: Anti-Paradoja Temporal (NUEVA)
	IF _Fecha_Min > _Fecha_Max THEN
		SIGNAL SQLSTATE '45000' 
		SET MESSAGE_TEXT = 'ERROR [400]: La fecha de inicio no puede ser posterior a la fecha de fin.';
	END IF;
    
    PARA VALIDAR EL SP_ConsultarCapacitacionEspecifica:
    
         ================================================================================================
       BLOQUE 1: DEFENSA EN PROFUNDIDAD Y VALIDACIÓN (FAIL FAST STRATEGY)
       Objetivo: Proteger el motor de base de datos rechazando peticiones incoherentes antes de procesar.
       ================================================================================================ 
    
     1.1 Validación de Integridad de Tipos (Type Safety Check) 
     Evitamos la ejecución de planes de consulta costosos si el input es nulo o negativo. 
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El Identificador de la capacitación es inválido.';
    END IF;

     1.2 Descubrimiento Jerárquico (Parent Discovery Logic) 
     Buscamos a qué "Expediente" (Padre) pertenece esta "Hoja" (Versión). 
       Utilizamos una consulta optimizada por índice primario para obtener el `Fk_Id_Capacitacion`. 
    SELECT `Fk_Id_Capacitacion` INTO v_Id_Padre_Capacitacion
    FROM `DatosCapacitaciones`
    WHERE `Id_DatosCap` = _Id_Detalle_Capacitacion
    LIMIT 1;

     1.3 Verificación de Existencia (404 Not Found Handling) 
     Si la variable sigue siendo NULL después del SELECT, significa que el registro no existe físicamente.
       Lanzamos un error semántico para informar al Frontend y detener la ejecución. 
    IF v_Id_Padre_Capacitacion IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La capacitación solicitada no existe en los registros.';
    END IF;

PARA VALIDAR EL SP_Editar_Capacitacion:

     ============================================================================================
       BLOQUE 0: SANITIZACIÓN Y VALIDACIONES LÓGICAS (PRE-FLIGHT CHECK)
       Objetivo: Validar la coherencia de los datos antes de tocar la estructura.
       ============================================================================================ 
    
     0.1 Limpieza de Strings 
    SET _Observaciones = NULLIF(TRIM(_Observaciones), '');

     0.2 Validación Temporal (Time Integrity) 
     Regla: El tiempo es lineal. El inicio no puede ser posterior al fin. 
    IF _Fecha_Inicio > _Fecha_Fin THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: Fechas inválidas. La fecha de inicio es posterior a la fecha de fin.';
    END IF;

     0.3 Validación de Justificación (Forensic Compliance) 
     Regla: No se permite alterar la historia sin dejar una razón documentada. 
    IF _Observaciones IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE AUDITORÍA [400]: La justificación (Observaciones) es obligatoria para realizar un cambio de versión.';
    END IF;

     ============================================================================================
       BLOQUE 1: VALIDACIÓN DE INTEGRIDAD ESTRUCTURAL (EL BLINDAJE)
       Objetivo: Evitar la corrupción del árbol genealógico del curso (Relación Padre-Hijo).
       ============================================================================================ 

     1.1 Descubrimiento del Contexto (Parent & State Discovery) 
     Buscamos quién es el padre y en qué estado está la versión que queremos editar. 
    SELECT `Fk_Id_Capacitacion`, `Activo` 
    INTO v_Id_Padre, v_Version_Es_Vigente
    FROM `DatosCapacitaciones` 
    WHERE `Id_DatosCap` = _Id_Version_Anterior 
    LIMIT 1;

     1.2 Verificación de Existencia (404 Handling) 
    IF v_Id_Padre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [404]: La versión que intenta editar no existe en los registros. Por favor refresque su navegador.';
    END IF;

     1.3 Verificación de Vigencia (Concurrency Protection) 
     [ESTRATEGIA ANTI-CORRUPCIÓN]: Si v_Version_Es_Vigente es 0, significa que esta versión YA FUE
       archivada por otra transacción. No podemos editar un registro histórico ("cadáver").
       Esto previene bifurcaciones en la línea de tiempo. 
    IF v_Version_Es_Vigente = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE INTEGRIDAD [409]: La versión que intenta editar YA NO ES VIGENTE. Alguien más modificó este curso recientemente. Por favor actualice la página para ver la última versión.';
    END IF;

     ============================================================================================
       BLOQUE 2: VALIDACIÓN DE RECURSOS (ANTI-ZOMBIE RESOURCES CHECK)
       Objetivo: Asegurar que no se asignen recursos (Instructores, Sedes) dados de baja.
       Se realizan consultas puntuales para verificar `Activo = 1` en cada catálogo.
       ============================================================================================ 
    
     2.1 Verificación de Instructor 
     Nota: Se valida tanto el Usuario como su InfoPersonal asociada. 
    SELECT I.Activo INTO v_Es_Activo 
    FROM Usuarios U 
    INNER JOIN Info_Personal I ON U.Fk_Id_InfoPersonal = I.Id_InfoPersonal 
    WHERE U.Id_Usuario = _Id_Instructor LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: El Instructor seleccionado está inactivo o ha sido dado de baja.'; 
    END IF;

     2.2 Verificación de Sede 
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Cases_Sedes` WHERE `Id_CatCases_Sedes` = _Id_Sede LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: La Sede seleccionada está clausurada o inactiva.'; 
    END IF;

     2.3 Verificación de Modalidad 
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = _Id_Modalidad LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: La Modalidad seleccionada no es válida actualmente.'; 
    END IF;

     2.4 Verificación de Estatus 
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = _Id_Estatus LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: El Estatus seleccionado está obsoleto o inactivo.'; 
    END IF;

VALIDAR EL SP_CambiarEstatusCapacitacion:


     ===============================================================================================
       BLOQUE 2: CAPA 1 - VALIDACIÓN DE PARÁMETROS DE ENTRADA (INPUT VALIDATION - FAIL FAST)
       ===============================================================================================
       
       [PROPÓSITO]:
       Rechazar peticiones con datos inválidos ANTES de realizar cualquier operación costosa
       (SELECTs a la BD, transacciones, etc.).
       
       [FILOSOFÍA - FAIL FAST]:
       "Falla rápido, falla ruidosamente". Es mejor rechazar inmediatamente una petición
       malformada que descubrir el error después de haber hecho trabajo innecesario.
       
       [PRINCIPIO DE DEFENSA EN PROFUNDIDAD]:
       Aunque el Frontend y el Backend DEBERÍAN validar estos datos antes de llamar al SP,
       no confiamos ciegamente en ellos. El SP es la última línea de defensa.
       
       [VALIDACIONES REALIZADAS]:
         1. _Id_Capacitacion: NOT NULL y > 0
         2. _Id_Usuario_Ejecutor: NOT NULL y > 0
         3. _Nuevo_Estatus: NOT NULL y IN (0, 1)
       =============================================================================================== 
    
     -----------------------------------------------------------------------------------------------
       VALIDACIÓN 2.1: INTEGRIDAD DEL ID DE CAPACITACIÓN
       ----------------------------------------------------------------------------------------------- 
     [REGLA]     : El ID del expediente debe ser un entero positivo válido.
       [CASOS RECHAZADOS]:
         - NULL: El Frontend no envió el parámetro o lo envió vacío.
         - 0: Valor por defecto que indica "ningún registro seleccionado".
         - Negativos: Imposibles en una columna AUTO_INCREMENT.
       [CÓDIGO DE ERROR]: [400] Bad Request - Datos de entrada inválidos.
       [ACCIÓN DEL CLIENTE]: Debe verificar que se haya seleccionado un registro válido. 
    IF _Id_Capacitacion IS NULL OR _Id_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID de la Capacitación es inválido o nulo. Verifique que haya seleccionado un registro válido del listado.';
    END IF;

     -----------------------------------------------------------------------------------------------
       VALIDACIÓN 2.2: INTEGRIDAD DEL ID DE USUARIO EJECUTOR
       ----------------------------------------------------------------------------------------------- 
     [REGLA]     : El ID del usuario auditor debe ser un entero positivo válido.
       [CASOS RECHAZADOS]:
         - NULL: El Backend no extrajo correctamente el ID de la sesión.
         - 0 o negativos: Valores imposibles para un usuario autenticado.
       [CÓDIGO DE ERROR]: [400] Bad Request - Datos de entrada inválidos.
       [IMPLICACIÓN]: Sin este ID, no podemos registrar quién realizó la acción (auditoría rota).
       [ACCIÓN DEL CLIENTE]: El Backend debe verificar la sesión del usuario antes de llamar. 
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID del Usuario Ejecutor es obligatorio para la auditoría. Verifique la sesión del usuario autenticado.';
    END IF;

     -----------------------------------------------------------------------------------------------
       VALIDACIÓN 2.3: INTEGRIDAD Y DOMINIO DEL NUEVO ESTATUS
       ----------------------------------------------------------------------------------------------- 
     [REGLA]     : El parámetro de acción debe ser explícitamente 0 (Archivar) o 1 (Restaurar).
       [CASOS RECHAZADOS]:
         - NULL: El Frontend no especificó qué acción realizar.
         - Valores distintos de 0 o 1: Dominio no permitido (ej: 2, -1, 99).
       [CÓDIGO DE ERROR]: [400] Bad Request - Datos de entrada inválidos.
       [JUSTIFICACIÓN v2.0]: Este parámetro es NUEVO. Reemplaza el comportamiento "toggle" de v1.0
                             que infería la acción. Ahora requerimos intención explícita.
       [ACCIÓN DEL CLIENTE]: El Frontend debe enviar 0 para archivar o 1 para restaurar. 
    IF _Nuevo_Estatus IS NULL OR _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: El campo "Nuevo Estatus" es obligatorio y solo acepta valores binarios: 0 (Archivar) o 1 (Restaurar). Verifique el valor enviado.';
    END IF;

     ===============================================================================================
       BLOQUE 3: CAPA 2 - RECUPERACIÓN DE CONTEXTO Y VERIFICACIÓN DE EXISTENCIA
       ===============================================================================================
       
       [PROPÓSITO]:
       Obtener toda la información necesaria sobre el expediente ANTES de tomar decisiones.
       Esto incluye:
         1. Verificar que el expediente existe (protección contra IDs fantasma).
         2. Obtener el estado actual del Padre (Activo/Archivado).
         3. Obtener metadatos para auditoría (Folio, Gerencia).
       
       [ESTRATEGIA - SINGLE QUERY OPTIMIZATION]:
       En lugar de hacer múltiples SELECTs pequeños, consolidamos todo en una sola consulta
       con JOIN para minimizar los round-trips a la base de datos.
       
       [BLOQUEO DE LECTURA]:
       Esta consulta NO usa FOR UPDATE porque solo estamos leyendo. El bloqueo pesimista
       se aplicará más adelante dentro de la transacción si es necesario.
       =============================================================================================== 
    
     -----------------------------------------------------------------------------------------------
       CONSULTA 3.1: RADIOGRAFÍA DEL PADRE + DATOS DE AUDITORÍA
       -----------------------------------------------------------------------------------------------
       [OBJETIVO]    : Obtener el estado actual y los datos de identificación del expediente.
       [TABLAS]      : 
         - `Capacitaciones` (Padre): Estado actual, Folio.
         - `Cat_Gerencias_Activos` (Catálogo): Clave de la gerencia para auditoría.
       [JOIN]        : INNER JOIN porque la FK de gerencia es obligatoria (no puede haber huérfanos).
       [LIMIT 1]     : Optimización. Aunque el ID es único, LIMIT evita scans innecesarios.
       [INTO]        : Carga los resultados en variables locales para uso posterior.
       ----------------------------------------------------------------------------------------------- 
    SELECT 
        `Cap`.`Activo`,              -- Estado actual del expediente (1=Activo, 0=Archivado)
        `Cap`.`Numero_Capacitacion`, -- Folio para mensajes y auditoría
        `Ger`.`Clave`                -- Clave de gerencia para nota de auditoría
    INTO 
        v_Estado_Actual_Padre,       -- Variable: Estado actual
        v_Folio,                     -- Variable: Folio
        v_Clave_Gerencia             -- Variable: Gerencia
    FROM `Capacitaciones` `Cap`
     -----------------------------------------------------------------------------------------
       JOIN CON CATÁLOGO DE GERENCIAS
       -----------------------------------------------------------------------------------------
       [TIPO]   : INNER JOIN (obligatorio)
       [RAZÓN]  : Todo expediente DEBE tener una gerencia asignada (FK NOT NULL).
       [TABLA]  : Cat_Gerencias_Activos - Catálogo maestro de gerencias.
       [COLUMNA]: Clave - Identificador de negocio de la gerencia (ej: "GER-FINANZAS").
       ----------------------------------------------------------------------------------------- 
    INNER JOIN `Cat_Gerencias_Activos` `Ger` 
        ON `Cap`.`Fk_Id_CatGeren` = `Ger`.`Id_CatGeren`
    WHERE `Cap`.`Id_Capacitacion` = _Id_Capacitacion 
    LIMIT 1;

     -----------------------------------------------------------------------------------------------
       VALIDACIÓN 3.2: VERIFICACIÓN DE EXISTENCIA (404 NOT FOUND)
       -----------------------------------------------------------------------------------------------
       [REGLA]     : Si el SELECT no encontró registros, v_Estado_Actual_Padre será NULL.
       [CAUSA PROBABLE]:
         - El ID proporcionado nunca existió en la base de datos.
         - El registro fue eliminado físicamente (caso raro, DELETE está prohibido).
         - Error de sincronización entre Frontend y BD (cache desactualizado).
       [CÓDIGO DE ERROR]: [404] Not Found - Recurso no encontrado.
       [ACCIÓN DEL CLIENTE]: Refrescar la lista y seleccionar un registro válido.
       ----------------------------------------------------------------------------------------------- 
    IF v_Estado_Actual_Padre IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La Capacitación solicitada no existe en el catálogo maestro. Es posible que haya sido eliminada o que el ID sea incorrecto. Por favor, actualice su listado.';
    END IF;

     ===============================================================================================
       BLOQUE 4: CAPA 3 - VERIFICACIÓN DE IDEMPOTENCIA
       ===============================================================================================
       
       [PROPÓSITO]:
       Evitar operaciones redundantes que no tendrían efecto en la base de datos.
       
       [DEFINICIÓN DE IDEMPOTENCIA]:
       Una operación es idempotente si ejecutarla múltiples veces produce el mismo resultado
       que ejecutarla una sola vez. En este contexto:
         - Archivar un expediente ya archivado = Sin cambios.
         - Restaurar un expediente ya activo = Sin cambios.
       
       [BENEFICIOS]:
         1. Evita escrituras innecesarias en la BD (optimización de I/O).
         2. Evita generar notas de auditoría duplicadas.
         3. Proporciona feedback claro al usuario sobre el estado actual.
       
       [COMPORTAMIENTO]:
       Si el estado actual ya coincide con el solicitado, el SP:
         1. Retorna un mensaje informativo (no un error).
         2. Sale anticipadamente con `LEAVE THIS_PROC`.
         3. NO ejecuta ningún UPDATE ni transacción.
       =============================================================================================== 
    IF v_Estado_Actual_Padre = _Nuevo_Estatus THEN
         -------------------------------------------------------------------------------------
           CONSTRUCCIÓN DEL MENSAJE DE IDEMPOTENCIA
           -------------------------------------------------------------------------------------
           [OBJETIVO]: Informar al usuario que no hubo cambios y por qué.
           [FORMATO] : Incluye el folio para que el usuario confirme que es el registro correcto.
           [TONO]    : Informativo (AVISO), no de error. No es un problema, solo una observación.
           ------------------------------------------------------------------------------------- 
        SELECT 
            CONCAT(
                'AVISO: La Capacitación "', v_Folio, '" ya se encuentra en el estado solicitado (', 
                IF(_Nuevo_Estatus = 1, 'ACTIVO', 'ARCHIVADO'), 
                '). No se realizaron cambios.'
            ) AS Mensaje, 
            'SIN_CAMBIOS' AS Accion;
        
         -------------------------------------------------------------------------------------
           SALIDA ANTICIPADA (EARLY EXIT)
           -------------------------------------------------------------------------------------
           [ACCIÓN]  : Terminar la ejecución del SP inmediatamente.
           [EFECTO]  : No se ejecuta ningún código posterior (transacción, UPDATEs, etc.).
           [NOTA]    : Esto es más limpio que usar flags booleanos y condicionales anidados.
           ------------------------------------------------------------------------------------- 
        LEAVE THIS_PROC;
    END IF;
    
    
     ===============================================================================================
       BLOQUE 7: MOTOR DE DECISIÓN - BIFURCACIÓN POR ACCIÓN SOLICITADA
       ===============================================================================================
       
       [PROPÓSITO]:
       Ejecutar la lógica específica según la acción solicitada:
         - _Nuevo_Estatus = 0: Ejecutar flujo de ARCHIVADO.
         - _Nuevo_Estatus = 1: Ejecutar flujo de RESTAURACIÓN.
       
       [ESTRUCTURA]:
       IF-ELSE con dos ramas mutuamente excluyentes.
       =============================================================================================== 

     ===========================================================================================
       RAMA A: FLUJO DE ARCHIVADO (_Nuevo_Estatus = 0)
       ===========================================================================================
       [OBJETIVO]: Cambiar el expediente de ACTIVO a ARCHIVADO (Soft Delete).
       [VALIDACIÓN REQUERIDA]: El estatus actual debe tener Es_Final = 1.
       [ACCIONES]:
         1. Validar regla de negocio (Es_Final = 1).
         2. Construir nota de auditoría.
         3. Apagar Padre (Activo = 0).
         4. Apagar Hijo + Inyectar nota (Activo = 0, Observaciones += nota).
       =========================================================================================== 
    IF _Nuevo_Estatus = 0 THEN
        
         ---------------------------------------------------------------------------------------
           PASO 7.A.1: CAPA 4 - VALIDACIÓN DE REGLAS DE NEGOCIO (BUSINESS RULES ENFORCEMENT)
           ---------------------------------------------------------------------------------------
           [REGLA]        : Solo se pueden archivar cursos con estatus TERMINAL (Es_Final = 1).
           [JUSTIFICACIÓN]: Archivar un curso "vivo" (en ejecución) lo haría desaparecer del
                            Dashboard sin haber completado su ciclo de vida, generando confusión.
           [ESTATUS PERMITIDOS]: FINALIZADO, CANCELADO, ARCHIVADO (Es_Final = 1).
           [ESTATUS BLOQUEADOS]: PROGRAMADO, EN CURSO, EVALUACIÓN, etc. (Es_Final = 0).
           --------------------------------------------------------------------------------------- 
        IF v_Es_Estatus_Final = 0 OR v_Es_Estatus_Final IS NULL THEN
             -----------------------------------------------------------------------------------
               ROLLBACK PREVENTIVO
               -----------------------------------------------------------------------------------
               [ACCIÓN] : Revertir la transacción antes de lanzar el error.
               [RAZÓN]  : Aunque no hemos hecho UPDATEs aún, es buena práctica cerrar la
                          transacción limpiamente antes de terminar el SP.
               ----------------------------------------------------------------------------------- 
            ROLLBACK;
            
             -----------------------------------------------------------------------------------
               CONSTRUCCIÓN DE MENSAJE DE ERROR DESCRIPTIVO
               -----------------------------------------------------------------------------------
               [OBJETIVO]: Dar al usuario información ACCIONABLE sobre cómo resolver el problema.
               [CONTENIDO]:
                 - Qué falló: "No se puede archivar un curso activo."
                 - Por qué: El estatus actual ("EN CURSO") es operativo, no final.
                 - Cómo resolverlo: "Debe finalizar o cancelar la capacitación antes."
               ----------------------------------------------------------------------------------- 
            SET @ErrorMsg = CONCAT(
                'ACCIÓN DENEGADA [409]: No se puede archivar un curso activo. ',
                'El estatus actual es "', v_Nombre_Estatus, '", el cual se considera OPERATIVO (No Final). ',
                'Debe finalizar o cancelar la capacitación antes de archivarla.'
            );
            
             -----------------------------------------------------------------------------------
               LANZAMIENTO DE EXCEPCIÓN CONTROLADA
               -----------------------------------------------------------------------------------
               [SQLSTATE 45000]: Código estándar para errores definidos por el usuario.
               [MESSAGE_TEXT] : El mensaje construido arriba.
               [EFECTO]       : El SP termina inmediatamente. El Backend captura este error.
               ----------------------------------------------------------------------------------- 
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @ErrorMsg;
        END IF;

         ---------------------------------------------------------------------------------------
           PASO 7.A.2: CONSTRUCCIÓN DE NOTA DE AUDITORÍA (AUDIT EVIDENCE PREPARATION)
           ---------------------------------------------------------------------------------------
           [PROPÓSITO]: Crear el texto que se inyectará en el campo Observaciones.
           [DATOS INCLUIDOS]:
             - Folio del curso (identificación).
             - Gerencia responsable (contexto organizacional).
             - Fecha y hora exacta (timestamp forense).
             - Motivo del archivado (justificación estándar).
           [FORMATO]: Texto plano con prefijo "[SISTEMA]:" para distinguirlo de notas manuales.
           --------------------------------------------------------------------------------------- 
        SET v_Mensaje_Auditoria = CONCAT(
            ' [SISTEMA]: La capacitación con folio ', v_Folio, 
            ' de la Gerencia ', v_Clave_Gerencia, 
            ', fue archivada el ', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), 
            ' porque alcanzó el fin de su ciclo de vida.'
        );
        
                 -----------------------------------------------------------------------------------
           PASO 7.A.5: RETORNO DE CONFIRMACIÓN AL CLIENTE
           -----------------------------------------------------------------------------------
           [FORMATO] : Resultset de fila única con 3 columnas.
           [USO]     : El Backend/Frontend usa estos valores para actualizar la UI.
           ----------------------------------------------------------------------------------- 
        SELECT 
            'ARCHIVADO' AS `Nuevo_Estado`,                                    -- Estado resultante
            'Expediente archivado y nota de auditoría registrada.' AS `Mensaje`, -- Feedback
            'ESTATUS_CAMBIADO' AS Accion;                                     -- Código de acción
            
            
PARA VALIDAR EL SP_EliminarCapacitacion :


	 ========================================================================================
       BLOQUE 1: HANDLERS DE EMERGENCIA (THE SAFETY NET)
       Propósito: Capturar errores nativos del motor InnoDB y darles un tratamiento humano.
       ======================================================================================== 
    
     [1.1] Handler para Error 1451 (Cannot delete or update a parent row: a foreign key constraint fails)
       Este es el cinturón de seguridad de la base de datos. Si nuestra validación lógica (Bloque 4) 
       fallara o si se agregaran nuevas tablas en el futuro sin actualizar este SP, el motor de BD 
       bloqueará el borrado. Este handler captura ese evento, deshace la transacción y da feedback. 
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN 
        ROLLBACK; -- Crucial: Liberar cualquier lock adquirido.
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE SISTEMA [1451]: Integridad Referencial Estricta detectada. La base de datos impidió la eliminación física porque existen vínculos en tablas del sistema (FK) no contempladas en la validación de negocio.'; 
    END;

     [1.2] Handler Genérico (Catch-All Exception)
       Objetivo: Capturar cualquier anomalía técnica (disco lleno, pérdida de conexión, etc.). 
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; -- Reenvía el error original para ser logueado por el Backend.
    END;

	 ========================================================================================
       BLOQUE 2: PROTOCOLO DE VALIDACIÓN PREVIA (FAIL FAST)
       Propósito: Identificar peticiones inválidas antes de comprometer recursos de servidor.
       ======================================================================================== 
    
     2.1 Validación de Tipado e Integridad de Entrada:
       Un ID nulo o negativo es una anomalía de la aplicación cliente que no debe procesarse. 
    IF _Id_Capacitacion IS NULL OR _Id_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El Identificador de Capacitación proporcionado es inválido o nulo.';
    END IF;
    
    
     ----------------------------------------------------------------------------------------
       PASO 3.1: VERIFICACIÓN DE EXISTENCIA Y BLOQUEO (FOR UPDATE)
       
       Objetivo: "Secuestrar" el registro padre (`Capacitaciones`).
       Efecto: Nadie puede inscribir alumnos, editar versiones o cambiar estatus de este curso
       mientras nosotros realizamos el análisis forense de eliminación.
       ---------------------------------------------------------------------------------------- 
    SELECT 1, `Numero_Capacitacion` 
    INTO v_Existe, v_Folio
    FROM `Capacitaciones`
    WHERE `Id_Capacitacion` = _Id_Capacitacion
    FOR UPDATE;

     Validación 404 
    IF v_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El curso que intenta eliminar no existe o ya fue borrado.';
    END IF;

     ----------------------------------------------------------------------------------------
       PASO 4.1: ESCANEO DE "NIETOS" (ALUMNOS/PARTICIPANTES)
       
       Lógica de Negocio:
       Buscamos si existen registros en `Capacitaciones_Participantes` (Nietos) que estén
       vinculados a cualquier `DatosCapacitaciones` (Hijos) que pertenezca a este Padre.
       
       Criterio Estricto:
       NO filtramos por estatus. Si un alumno reprobó hace 2 años en una versión archivada,
       eso cuenta como historia académica y BLOQUEA el borrado.
       ---------------------------------------------------------------------------------------- 
    SELECT COUNT(*) INTO v_Total_Alumnos
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    WHERE `DC`.`Fk_Id_Capacitacion` = _Id_Capacitacion;

     [PUNTO DE BLOQUEO]: Si el contador es mayor a 0, detenemos todo. 
    IF v_Total_Alumnos > 0 THEN
        ROLLBACK; -- Liberamos el bloqueo del padre inmediatamente.
        
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ACCIÓN DENEGADA [409]: Imposible eliminar. Existen participantes/alumnos registrados en el historial de este curso (incluso en versiones anteriores). Borrarlo destruiría su historial académico. Utilice la opción de "ARCHIVAR" en su lugar.';
    END IF;


PARA VALIDAR SP_RegistrarParticipanteCapacitacion:


     ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: MANEJO DE EXCEPCIONES Y ATOMICIDAD (ACID COMPLIANCE)
       Objetivo: Implementar un mecanismo de seguridad (Fail-Safe).
       Si ocurre cualquier error SQL crítico durante la ejecución, se revierte todo.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ 
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- [CRÍTICO]: Revertir cualquier cambio pendiente en la transacción actual.
        ROLLBACK;
        
        -- Retornar mensaje estandarizado de error 500 al cliente.
        SELECT 
            'ERROR DE SISTEMA [500]: Fallo interno crítico durante la transacción de inscripción.' AS Mensaje,
            'ERROR_TECNICO' AS Accion,
            NULL AS Id_Registro_Participante;
    END;

     ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN DE ENTRADA (INPUT SANITIZATION - FAIL FAST)
       Objetivo: Validar la integridad estructural de los datos antes de procesar lógica de negocio.
       Esto ahorra recursos de CPU y Base de Datos al rechazar peticiones mal formadas inmediatamente.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ 
    
    -- Validación 0.1: Integridad del Ejecutor
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es obligatorio.' AS Mensaje, 
				   'VALIDACION_FALLIDA' AS Accion, 
                   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart; -- Terminación inmediata
    END IF;
    
    -- Validación 0.2: Integridad del Recurso (Curso)
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El ID de la Capacitación es obligatorio.' AS Mensaje, 
				   'VALIDACION_FALLIDA' AS Accion, 
                   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart; -- Terminación inmediata
    END IF;
    
    -- Validación 0.3: Integridad del Destinatario (Participante)
    IF _Id_Usuario_Participante IS NULL OR _Id_Usuario_Participante <= 0 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El ID del Participante es obligatorio.' AS Mensaje, 
				   'VALIDACION_FALLIDA' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart; -- Terminación inmediata
    END IF;

     ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: VERIFICACIÓN DE CREDENCIALES DEL EJECUTOR (SECURITY LAYER)
       Objetivo: Asegurar que la solicitud proviene de un actor válido en el sistema.
       No verificamos roles aquí (eso es capa de aplicación), pero sí existencia y actividad.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ 
    SELECT COUNT(*) INTO v_Ejecutor_Existe 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor 
      AND `Activo` = 1; -- Solo usuarios activos pueden ejecutar acciones
    
    IF v_Ejecutor_Existe = 0 
		THEN
			SELECT 'ERROR DE SEGURIDAD [403]: El Usuario Ejecutor no es válido o está inactivo.' AS Mensaje, 
				   'ACCESO_DENEGADO' AS Accion, 
                   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;

     ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: VERIFICACIÓN DE ELEGIBILIDAD DEL PARTICIPANTE (TARGET VALIDATION)
       Objetivo: Asegurar la integridad referencial del alumno destino.
       Regla de Negocio: No se puede inscribir a un usuario que ha sido dado de baja administrativamente.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ 
    SELECT COUNT(*), `Activo` 
    INTO v_Participante_Existe, v_Participante_Activo 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Participante;
    
    -- Validación 2.1: Existencia Física del Registro
    IF v_Participante_Existe = 0 
		THEN
			SELECT 'ERROR DE INTEGRIDAD [404]: El usuario a inscribir no existe en el sistema.' AS Mensaje, 
				   'RECURSO_NO_ENCONTRADO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;
    
    -- Validación 2.2: Estado Operativo del Usuario (Soft Delete Check)
    IF v_Participante_Activo = 0 
		THEN
			SELECT 'ERROR DE LÓGICA [409]: El usuario está INACTIVO (Baja Administrativa). No puede ser inscrito.' AS Mensaje, 
				   'CONFLICTO_ESTADO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;
    
        -- Validación 3.1: Integridad Referencial del Curso
    IF v_Capacitacion_Existe = 0 
		THEN 
			SELECT 'ERROR DE INTEGRIDAD [404]: La capacitación indicada no existe.' AS Mensaje, 
				   'RECURSO_NO_ENCONTRADO' AS Accion, 
                   NULL AS Id_Registro_Participante; 
        LEAVE ProcInsPart; 
    END IF;
    
    -- Validación 3.2: Integridad Lógica (Curso eliminado)
    IF v_Capacitacion_Activa = 0 
		THEN 
			SELECT 'ERROR DE LÓGICA [409]: Esta versión del curso está ARCHIVADA o eliminada.' AS Mensaje, 
				   'CONFLICTO_ESTADO' AS Accion, 
                   NULL AS Id_Registro_Participante; 
        LEAVE ProcInsPart; 
    END IF;
    
    
         ------------------------------------------------------------------------------------------------------
       [VALIDACIÓN DE LISTA NEGRA DE ESTATUS - BUSINESS RULE ENFORCEMENT]
       Aquí aplicamos la lógica específica para Admins. 
       A diferencia del usuario normal, el Admin PUEDE inscribir en cursos pasados (Finalizados, En Evaluación).
       
       SOLO se bloquea si el curso está:
       - CANCELADO (ID 8): Porque nunca ocurrió.
       - CERRADO/ARCHIVADO (ID 10): Porque el expediente administrativo ya se cerró.
       ------------------------------------------------------------------------------------------------------ 
    IF v_Estatus_Curso IN (c_CURSO_CANCELADO, c_CURSO_ARCHIVADO) 
		THEN
			SELECT 
				CONCAT('ERROR DE NEGOCIO [409]: No se puede modificar la lista de asistentes. El curso "', v_Folio_Curso, 
					   '" se encuentra en un estatus inoperable (ID: ', v_Estatus_Curso, ').') AS Mensaje, 
				'ESTATUS_PROHIBIDO' AS Accion, 
				NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;



     ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 4: VALIDACIÓN DE UNICIDAD (IDEMPOTENCY CHECK)
       Objetivo: Prevenir registros duplicados. Un alumno no puede ocupar dos asientos en el mismo curso.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ 
    SELECT COUNT(*) INTO v_Ya_Inscrito 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion 
      AND `Fk_Id_Usuario` = _Id_Usuario_Participante;
    
    IF v_Ya_Inscrito > 0 
		THEN 
			SELECT CONCAT('AVISO DE NEGOCIO: El usuario ya se encuentra registrado en el curso "', v_Folio_Curso, '".') AS Mensaje, 
				   'DUPLICADO' AS Accion, 
				   NULL AS Id_Registro_Participante; 
        LEAVE ProcInsPart; 
    END IF;
    
         ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 5: VALIDACIÓN DE CAPACIDAD (ALGORITMO DE CUPO HÍBRIDO)
       Objetivo: Determinar la disponibilidad real de asientos utilizando lógica pesimista.
       Nota: Incluso en correcciones históricas, respetamos la capacidad máxima del aula para no 
       generar inconsistencias en los reportes de ocupación.
       
       Fórmula: Disponible = Meta - MAX(Conteo_Sistema, Conteo_Manual)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ 
    
    -- Paso 5.1: Contar ocupación real en sistema (Excluyendo bajas)
    SELECT COUNT(*) INTO v_Conteo_Sistema 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion 
      AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

    -- Paso 5.2: Aplicar Regla del Máximo (Sistema vs Manual)
    -- Si el coordinador puso "30" manuales, y hay 5 en sistema, tomamos 30.
    SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);

    -- Paso 5.3: Calcular Delta
    SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
    
    -- Paso 5.4: Veredicto Final
    IF v_Cupo_Disponible <= 0 
		THEN 
			SELECT CONCAT('ERROR DE NEGOCIO [409]: CUPO LLENO en "', v_Folio_Curso, '". Ocupados: ', v_Asientos_Ocupados, '/', v_Cupo_Maximo, '.') AS Mensaje, 
				   'CUPO_LLENO' AS Accion, 
                   NULL AS Id_Registro_Participante; 
        LEAVE ProcInsPart; 
    END IF;
    
    PARA VALIDAR  EL SP_RegistrarParticipacionCapacitacion
    
    
     ═══════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: MANEJO DE EXCEPCIONES (EXCEPTION HANDLING & ACID PROTECTION)
       Objetivo: Garantizar la atomicidad. Si ocurre cualquier error SQL (Deadlock, Constraint, Type),
       se revierte toda la operación para no dejar "basura" o registros huérfanos.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ 
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK; -- [CRÍTICO]: Revertir transacción pendiente.
        SELECT 
            'ERROR DE SISTEMA [500]: Ocurrió un error técnico al procesar tu inscripción.' AS Mensaje,
            'ERROR_TECNICO' AS Accion,
            NULL AS Id_Registro_Participante;
    END;

     ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN DE ENTRADA (FAIL-FAST STRATEGY)
       Justificación: No tiene sentido iniciar transacciones ni lecturas si los datos básicos
       vienen corruptos (NULL o Ceros). Ahorra CPU y I/O.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ 
    
    -- Validación 0.1: Identidad del Solicitante
    IF _Id_Usuario IS NULL OR _Id_Usuario <= 0 
		THEN
			SELECT 'ERROR DE SESIÓN [400]: No se pudo identificar tu usuario. Por favor relogueate.' AS Mensaje, 
				   'LOGOUT_REQUIRED' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    -- Validación 0.2: Objetivo de la Transacción
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El curso seleccionado no es válido.' AS Mensaje, 
					'VALIDACION_FALLIDA' AS Accion, 
					NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

     ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: VERIFICACIÓN DE IDENTIDAD Y VIGENCIA (USER ASSERTION)
       Objetivo: Confirmar que el usuario existe en BD y tiene permiso de operar (Activo=1).
       Previene operaciones de usuarios inhabilitados que aún tengan sesión abierta.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ 
    SELECT COUNT(*), `Activo` 
    INTO v_Usuario_Existe, v_Usuario_Activo 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario;
    
    -- Validación 1.1: Existencia Física
    IF v_Usuario_Existe = 0 
		THEN
			SELECT 'ERROR DE CUENTA [404]: Tu usuario no parece existir en el sistema.' AS Mensaje, 
				   'CONTACTAR_SOPORTE' AS Accion, 
                   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    -- Validación 1.2: Estado Lógico (Soft Delete Check)
    IF v_Usuario_Activo = 0 
		THEN
			SELECT 'ACCESO DENEGADO [403]: Tu cuenta está inactiva. No puedes inscribirte.' AS Mensaje, 
				   'ACCESO_DENEGADO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
         ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: CONTEXTO Y ESTADO DEL CURSO (RESOURCE AVAILABILITY SNAPSHOT)
       Objetivo: Cargar todos los metadatos del curso en memoria para validaciones complejas.
       Optimizacion: Se hace un solo SELECT con JOIN implícito para evitar múltiples round-trips a la BD.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ 
    SELECT 
        COUNT(*),                             -- [0] Existe?
        COALESCE(`DC`.`Activo`, 0),           -- [1] Activo?
        `DC`.`Fk_Id_Capacitacion`,            -- [2] ID Padre
        `DC`.`Fk_Id_CatEstCap`,               -- [3] Status ID (Para Whitelist)
        COALESCE(`DC`.`AsistentesReales`, 0)  -- [4] Override Manual (Input Coordinador)
    INTO 
        v_Capacitacion_Existe, 
        v_Capacitacion_Activa, 
        v_Id_Capacitacion_Padre, 
        v_Estatus_Curso, 
        v_Conteo_Manual
    FROM `DatosCapacitaciones` `DC` 
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

    -- Validación 2.1: Integridad Referencial
    IF v_Capacitacion_Existe = 0 
		THEN
			SELECT 'ERROR [404]: El curso que buscas no existe.' AS Mensaje, 
				   'RECURSO_NO_ENCONTRADO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    -- Validación 2.2: Ciclo de Vida (Soft Delete)
    IF v_Capacitacion_Activa = 0 
		THEN
			SELECT 'LO SENTIMOS [409]: Este curso ha sido archivado o cancelado.' AS Mensaje, 
				   'CURSO_CERRADO' AS Accion, 
                   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    -- Obtener Meta y Folio (Sub-Consulta Optimizada)
    SELECT `Numero_Capacitacion`, `Asistentes_Programados` INTO v_Folio_Curso, v_Cupo_Maximo 
    FROM `Capacitaciones` WHERE `Id_Capacitacion` = v_Id_Capacitacion_Padre;
    
    -- Validación 2.3: Ciclo de Vida del Negocio (Estatus Final)
    SELECT `Es_Final` INTO v_Es_Estatus_Final 
    FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = v_Estatus_Curso;
    
    IF v_Es_Estatus_Final = 1 
		THEN
			SELECT CONCAT('INSCRIPCIONES CERRADAS: El curso "', v_Folio_Curso, '" ya ha finalizado.') AS Mensaje, 
				   'CURSO_CERRADO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

     [VALIDACIÓN CRÍTICA] 2.4: Estatus Operativo Permitido (Whitelist)
       Objetivo: Evitar inscribir en cursos "En Diseño", "En Curso" (ya iniciados) o estatus no comerciales.
       Solo se permite: PROGRAMADO (1), POR INICIAR (2), REPROGRAMADO (9).
    
    IF v_Estatus_Curso NOT IN (c_EST_PROGRAMADO, c_EST_POR_INICIAR, c_EST_REPROGRAMADO) 
		THEN
			SELECT CONCAT('AÚN NO DISPONIBLE: El curso "', v_Folio_Curso, '" no está abierto para inscripciones (Estatus actual: ', v_Estatus_Curso, ').') AS Mensaje, 
				   'ESTATUS_INVALIDO' AS Accion,
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

     ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: VALIDACIÓN DE IDEMPOTENCIA (UNIQUENESS CHECK)
       Objetivo: Asegurar que el usuario no se inscriba dos veces al mismo curso.
       Regla: Un usuario puede tener N cursos, pero solo 1 registro activo por Curso específico.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ 
    SELECT COUNT(*) INTO v_Ya_Inscrito 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion 
      AND `Fk_Id_Usuario` = _Id_Usuario;
    
    IF v_Ya_Inscrito > 0 THEN
        SELECT 'YA ESTÁS INSCRITO: Ya tienes un lugar reservado en este curso.' AS Mensaje, 
               'YA_INSCRITO' AS Accion, 
               NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

     ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 4: CÁLCULO Y VALIDACIÓN DE CUPO (HYBRID CAPACITY LOGIC)
       Objetivo: Determinar disponibilidad real aplicando la regla "GREATEST".
       
       Escenario de Protección:
       - Meta = 20
       - Sistema (Inscritos) = 5
       - Manual (Coordinador) = 20 (Porque sabe que viene un grupo externo).
       - Cálculo: GREATEST(5, 20) = 20 ocupados.
       - Disponible: 20 - 20 = 0.
       - Resultado: CUPO LLENO (Correcto, bloquea al usuario aunque el sistema vea 5).
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ 
    
    -- Paso 4.1: Contar ocupación sistémica (Excluyendo bajas que liberan cupo)
    SELECT COUNT(*) INTO v_Conteo_Sistema 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion 
      AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

    -- Paso 4.2: Aplicar Regla del Máximo (Pesimista)
    SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);

    -- Paso 4.3: Calcular disponibilidad neta
    SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
    
    -- Paso 4.4: Veredicto Final
    IF v_Cupo_Disponible <= 0 
		THEN
			SELECT 'CUPO LLENO: Lo sentimos, ya no hay lugares disponibles para este curso.' AS Mensaje, 
				   'CUPO_LLENO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    PARA VALIDAR EL SP_ConsularMisCursos:
    
        
     ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN DE ENTRADA
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ 
    IF _Id_Usuario IS NULL OR _Id_Usuario <= 0 
		THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario es obligatorio para la consulta.' AS Mensaje, 
               'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcMisCursos;
    END IF;
    
    PARA VALIDAR EL SP_ConsultarCursosImpartidos:
    
        
     ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN DE IDENTIDAD
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ 
    IF _Id_Instructor IS NULL OR _Id_Instructor <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Instructor es obligatorio para recuperar el historial.' AS Mensaje,
               'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcCursosImpart;
    END IF;

PARA VALIDAR EL SP_EditarParticipanteCapacitacion:

     ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: HANDLER DE SEGURIDAD TRANSACCIONAL (ACID PROTECTION)
       Este bloque es el peritaje automático ante fallos del motor InnoDB o de red.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ 
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- [FORENSIC ACTION]: Ante cualquier error inesperado, revierte los cambios iniciados.
        ROLLBACK;
        -- Emite una señal de error 500 para la capa de servicios de la aplicación.
        SELECT 
            'ERROR TÉCNICO [500]: Fallo crítico detectado por el motor de BD al asentar resultados.' AS Mensaje, 
            'ERROR_TECNICO' AS Accion;
    END;

     ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN FORENSE (FAIL-FAST STRATEGY)
       Rechaza la petición antes de comprometer la integridad del Snapshot.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ 
    
    -- [0.1] Validación de Identificadores (Punteros de Memoria)
    -- Se prohíbe el uso de IDs nulos o negativos que puedan causar lecturas inconsistentes.
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es inválido.' AS Mensaje, 
			'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;
    
    IF _Id_Registro_Participante IS NULL OR _Id_Registro_Participante <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: El ID del Registro es inválido.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;

    -- [0.2] Validación de Integridad de Escala (Rango Numérico)
    -- Asegura que los datos sigan la escala decimal estándar del 0 al 100.
    IF (_Calificacion IS NOT NULL AND (_Calificacion < 0 OR _Calificacion > 100)) OR 
       (_Porcentaje_Asistencia IS NOT NULL AND (_Porcentaje_Asistencia < 0 OR _Porcentaje_Asistencia > 100)) 
		THEN
			SELECT 'ERROR DE RANGO [400]: Las notas y asistencias deben estar entre 0.00 y 100.00.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcUpdatResulPart;
    END IF;

    -- [0.3] Validación de Cumplimiento (Compliance Check)
    -- Exige que cada cambio en la historia académica del alumno esté fundamentado.
    IF _Justificacion_Cualitativa IS NULL OR TRIM(_Justificacion_Cualitativa) = '' 
		THEN
			SELECT 'ERROR DE AUDITORÍA [400]: Es obligatorio proporcionar un motivo para este cambio de resultados.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;

     ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: CAPTURA DE SNAPSHOT ACADÉMICO (READ BEFORE WRITE)
       Recopila los datos actuales de las tablas físicas hacia las variables locales de memoria.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ 
    
    -- [1.1] Verificación de Existencia y Actividad del Ejecutor
    -- Confirmamos que quien califica es un usuario válido y no ha sido inhabilitado.
    SELECT COUNT(*) 
    INTO v_Ejecutor_Existe 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor 
    AND `Activo` = 1;
    
    IF v_Ejecutor_Existe = 0 
		THEN 
			SELECT 'ERROR DE PERMISOS [403]: El usuario ejecutor no posee credenciales activas.' AS Mensaje, 
            'ACCESO_DENEGADO' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;
    
    -- [1.2] Hidratación de Variables de la Inscripción (Snapshot Forense)
    -- Recupera la nota previa, asistencia previa y estatus actual para el análisis de cambio.
    SELECT 
        COUNT(*), 
        `CP`.`Fk_Id_CatEstPart`, 
        `CP`.`Calificacion`, 
        `CP`.`PorcentajeAsistencia`,
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`), 
        `C`.`Numero_Capacitacion`
    INTO 
        v_Registro_Existe, 
        v_Estatus_Actual, 
        v_Calificacion_Previa, 
        v_Asistencia_Previa,
        v_Nombre_Alumno, 
        v_Folio_Curso
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    INNER JOIN `Capacitaciones` `C` ON `DC`.`Fk_Id_Capacitacion` = `C`.`Id_Capacitacion`
    INNER JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    INNER JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPer` = `IP`.`Id_InfoPer`
    WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;

    -- [1.3] Validación de Existencia de Matrícula
    -- Si la consulta no devolvió filas, el ID enviado es erróneo.
    IF v_Registro_Existe = 0 
		THEN 
			SELECT 'ERROR DE INTEGRIDAD [404]: El registro de matrícula solicitado no existe en BD.' AS Mensaje, 
            'RECURSO_NO_ENCONTRADO' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;

    -- [1.4] Protección contra Modificación de Bajas (Immutability Layer)
    -- Un alumno en BAJA ha liberado su lugar; calificarlo rompería la lógica del ciclo de vida.
    IF v_Estatus_Actual = c_EST_BAJA 
		THEN
			SELECT CONCAT('ERROR DE NEGOCIO [409]: Imposible calificar a "', v_Nombre_Alumno, '" porque se encuentra en BAJA.') AS Mensaje, 
            'CONFLICTO_ESTADO' AS Accion;
        LEAVE ProcUpdatResulPart;
    END IF;

     ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: MÁQUINA DE ESTADOS Y CÁLCULO DE AUDITORÍA (BUSINESS LOGIC ENGINE)
       Calcula el nuevo estatus y construye la traza forense acumulativa.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ 
    
    -- [2.1] Determinación de Nuevo Estatus (Hierarchical Logic)
    -- El sistema evalúa qué camino tomar basado en los parámetros recibidos.
    IF _Id_Estatus_Resultado IS NOT NULL THEN
        -- CAMINO 1: OVERRIDE MANUAL. La voluntad del Admin es ley.
        SET v_Nuevo_Estatus_Calculado = _Id_Estatus_Resultado;
    
    ELSEIF _Calificacion IS NOT NULL THEN
        -- CAMINO 2: CÁLCULO ANALÍTICO. Se evalúa el desempeño académico contra el umbral de aprobación.
        IF _Calificacion >= c_UMBRAL_APROBACION THEN 
            SET v_Nuevo_Estatus_Calculado = c_EST_APROBADO;
        ELSE 
            SET v_Nuevo_Estatus_Calculado = c_EST_REPROBADO; 
        END IF;
    
    ELSEIF _Porcentaje_Asistencia IS NOT NULL AND v_Estatus_Actual = 1 THEN
        -- CAMINO 3: AVANCE LOGÍSTICO. Si el alumno está "Inscrito" y se pone asistencia, avanza a "Asistió".
        SET v_Nuevo_Estatus_Calculado = c_EST_ASISTIO;
    
    ELSE
        -- CAMINO 4: PRESERVACIÓN. No hay cambios de estado, se mantiene el actual.
        SET v_Nuevo_Estatus_Calculado = v_Estatus_Actual;
    END IF;

    -- [2.2] Construcción de Inyección Forense (Serialized Audit Note)
    -- Genera una cadena detallada que permite reconstruir la operación sin consultar logs secundarios.
    SET v_Audit_Trail_Final = CONCAT(
        'EDIT_RES [', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), ']: ',
        'NOTA_ACT: ', COALESCE(_Calificacion, v_Calificacion_Previa, '0.00'), 
        ' | ASIST_ACT: ', COALESCE(_Porcentaje_Asistencia, v_Asistencia_Previa, '0.00'), '%',
        ' | MOTIVO: ', _Justificacion_Cualitativa
    );


PARA VALIDAR EL SP_CambiarEstatusParticipanteCapacitacion:


     ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: HANDLER DE SEGURIDAD TRANSACCIONAL (ACID EXCEPTION PROTECTION)
       Mecanismo de recuperación que se dispara ante fallos de integridad, red o motor de BD.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ 
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- [FORENSIC ACTION]: Si la transacción falló, revierte inmediatamente cualquier escritura en disco.
        ROLLBACK;
        
        -- Retorna una estructura de error estandarizada para el log de la aplicación.
        SELECT 
            'ERROR TÉCNICO [500]: Fallo crítico detectado por el motor InnoDB al intentar alternar el estatus.' AS Mensaje, 
            'ERROR_TECNICO' AS Accion;
    END;

     ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN ESTRUCTURAL (FAIL-FAST STRATEGY)
       Rechaza la petición si los parámetros de entrada no cumplen con la estructura básica esperada.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ 
    
    -- [0.1] Validación del ID del Ejecutor: No se permiten nulos ni valores menores o iguales a cero.
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es inválido o nulo.' AS Mensaje, 
				'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; -- Termina el proceso ahorrando ciclos de servidor.
    END IF;
    
    -- [0.2] Validación del ID de Registro: Asegura que el puntero a la tabla de relación sea procesable.
    IF _Id_Registro_Participante IS NULL OR _Id_Registro_Participante <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: El ID del Registro de Participante es inválido o nulo.' AS Mensaje, 
				'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;

    -- [0.3] Validación de Dominio de Estatus: Solo se permite alternar entre INSCRITO y BAJA.
    IF _Nuevo_Estatus_Deseado NOT IN (c_ESTATUS_INSCRITO, c_ESTATUS_BAJA) 
		THEN
			SELECT 'ERROR DE NEGOCIO [400]: El estatus solicitado no es válido para este interruptor operativo.' AS Mensaje, 
				'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- [0.4] Validación de Justificación: No se permiten cambios de estatus sin una razón documentada.
    IF _Motivo_Cambio IS NULL OR TRIM(_Motivo_Cambio) = '' 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El motivo del cambio es obligatorio para fines de trazabilidad forense.' AS Mensaje, 
				'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;

     ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: CAPTURA DE CONTEXTO Y SEGURIDAD (SNAPSHOT DE DATOS FORENSES)
       Carga el estado del mundo real en variables locales para ejecutar validaciones complejas.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ 
    
    -- [1.1] Validación de Identidad del Administrador
    -- Confirmamos que el ejecutor es un usuario real y está en estado ACTIVO en el sistema.
    SELECT COUNT(*) 
    INTO v_Ejecutor_Existe 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor 
		AND `Activo` = 1;
    
    IF v_Ejecutor_Existe = 0 
		THEN 
			SELECT 'ERROR DE PERMISOS [403]: El Usuario Ejecutor no tiene privilegios activos para modificar matriculaciones.' AS Mensaje, 
				'ACCESO_DENEGADO' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- [1.2] Hidratación Masiva del Snapshot (Single Round-Trip Optimization)
    -- Se recupera la información del alumno, su estatus, su nota y el estado del curso en un solo query.
    SELECT 
        COUNT(*),                               -- [0] Verificador físico de existencia.
        COALESCE(`CP`.`Fk_Id_CatEstPart`, 0),   -- [1] Estatus actual del alumno (Toggle Source).
        `CP`.`Fk_Id_DatosCap`,                  -- [2] FK al detalle operativo de la capacitación.
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`), -- [3] Nombre completo para feedback UX.
        CASE WHEN `CP`.`Calificacion` IS NOT NULL THEN 1 ELSE 0 END, -- [4] FLAG: ¿Alumno ya evaluado?
        `DC`.`Activo`,                          -- [5] FLAG: ¿Curso borrado lógicamente?
        `DC`.`Fk_Id_CatEstCap`,                 -- [6] ID del estado operativo del curso.
        `DC`.`Fk_Id_Capacitacion`,              -- [7] FK a la cabecera para lectura de Metas.
        COALESCE(`DC`.`AsistentesReales`, 0)    -- [8] Conteo manual capturado por el Coordinador.
    INTO 
        v_Registro_Existe,
        v_Estatus_Actual_Alumno,
        v_Id_Detalle_Curso,
        v_Nombre_Alumno,
        v_Tiene_Calificacion,
        v_Curso_Activo,
        v_Estatus_Curso,
        v_Id_Padre,
        v_Conteo_Manual
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    INNER JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    INNER JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPer` = `IP`.`Id_InfoPer`
    WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;

    -- [1.3] Validación de Integridad Física: Si el conteo es 0, el registro solicitado no existe.
    IF v_Registro_Existe = 0 
		THEN 
			SELECT 'ERROR DE EXISTENCIA [404]: No se encontró el expediente de inscripción solicitado en la base de datos.' AS Mensaje, 
            'RECURSO_NO_ENCONTRADO' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- [1.4] Validación de Idempotencia: Si el alumno ya está en el estado que se pide, no hacemos nada.
    IF v_Estatus_Actual_Alumno = _Nuevo_Estatus_Deseado 
		THEN
			SELECT CONCAT('AVISO DE SISTEMA: El alumno "', v_Nombre_Alumno, '" ya se encuentra en el estado solicitado. No se realizaron cambios.') AS Mensaje, 'SIN_CAMBIOS' AS Accion;
        LEAVE ProcTogglePart;
    END IF;

    -- [1.5] Recuperación de Metadatos de Planeación
    -- Cargamos el folio Numero_Capacitacion y el cupo máximo (Asistentes_Programados) de la tabla maestra.
    SELECT `Numero_Capacitacion`, 
		`Asistentes_Programados` 
    INTO v_Folio_Curso, 
		v_Cupo_Maximo
    FROM `Capacitaciones` 
    WHERE `Id_Capacitacion` = v_Id_Padre;

    -- [1.6] Validación de Protección de Ciclo de Vida
    -- Bloquea cualquier cambio de participante si el curso está en un estado terminal (Cancelado/Archivado).
    IF v_Estatus_Curso IN (c_CURSO_CANCELADO, c_CURSO_ARCHIVADO) 
		THEN
			SELECT CONCAT('ERROR DE LÓGICA [409]: La capacitación "', v_Folio_Curso, '" está administrativamente CERRADA. No se permite alterar la lista.') AS Mensaje, 'ESTATUS_PROHIBIDO' AS Accion;
        LEAVE ProcTogglePart;
    END IF;

     ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: PROCESAMIENTO DE BIFURCACIÓN LÓGICA (DECISION MATRIX)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ 
    
    -- [INICIO DEL ÁRBOL DE DECISIÓN]
    IF _Nuevo_Estatus_Deseado = c_ESTATUS_BAJA THEN
        
         ═══════════════════════════════════════════════════════════════════════════════════════════════
           RAMA A: PROCESO DE DESINCORPORACIÓN (DAR DE BAJA)
           ═══════════════════════════════════════════════════════════════════════════════════════════════ 
        -- [A.1] Validación de Integridad Académica (Constraint Academic Protection)
        -- Regla Forense: Un alumno con calificación registrada NO PUEDE ser dado de baja administrativamente.
        IF v_Tiene_Calificacion = 1 
			THEN
				SELECT CONCAT('ERROR DE INTEGRIDAD [409]: No se puede dar de baja a "', v_Nombre_Alumno, '" porque ya cuenta con una calificación final asentada.') AS Mensaje, 'CONFLICTO_ESTADO' AS Accion;
            LEAVE ProcTogglePart;
        END IF;

    ELSE
        
         ═══════════════════════════════════════════════════════════════════════════════════════════════
           RAMA B: PROCESO DE REINCORPORACIÓN (REINSCRIBIR)
           ═══════════════════════════════════════════════════════════════════════════════════════════════ 
        -- [B.1] Validación de Cupo Híbrido (Pessimistic Capacity Check)
        
        -- Contamos todos los participantes que NO están en baja para ver cuánto espacio queda disponible.
        SELECT COUNT(*) 
        INTO v_Conteo_Sistema 
        FROM `Capacitaciones_Participantes` 
        WHERE `Fk_Id_DatosCap` = v_Id_Detalle_Curso 
          AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

        -- Regla GREATEST(): Tomamos el escenario más ocupado entre el sistema automático y el manual del admin.
        SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);
        
        -- Calculamos la disponibilidad neta.
        SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
        
        -- Si no hay asientos, bloqueamos la reinscripción para proteger la integridad del aula.
        IF v_Cupo_Disponible <= 0 
			THEN
				SELECT CONCAT('ERROR DE CUPO [409]: Imposible reinscribir a "', v_Nombre_Alumno, '". La capacitación "', v_Folio_Curso, '" ha alcanzado su límite de aforo.') AS Mensaje, 'CUPO_LLENO' AS Accion;
            LEAVE ProcTogglePart;
        END IF;

    END IF;

     ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: INYECCIÓN DE AUDITORÍA Y PERSISTENCIA (ACID WRITE TRANSACTION)
       Objetivo: Escribir el cambio en disco garantizando que la operación sea Todo o Nada.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ 
    START TRANSACTION;
        -- Actualizamos el registro de matriculación.
        UPDATE `Capacitaciones_Participantes`
        SET `Fk_Id_CatEstPart` = _Nuevo_Estatus_Deseado, -- Aplicamos el nuevo estado solicitado.
            -- [AUDIT INJECTION]: Concatenamos la acción, el timestamp de sistema y el motivo para el peritaje histórico.
            `Justificacion` = CONCAT(
                CASE WHEN _Nuevo_Estatus_Deseado = c_ESTATUS_BAJA THEN 'BAJA_SISTEMA' ELSE 'REINSCRIBIR_SISTEMA' END,
                ' | FECHA: ', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), 
                ' | MOTIVO: ', _Motivo_Operacion
            ),
            -- Actualizamos los sellos de tiempo y autoría.
            `updated_at` = NOW(),
            `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
        WHERE `Id_CapPart` = _Id_Registro_Participante;
        
        -- Si llegamos aquí sin errores, el motor InnoDB confirma los cambios físicamente.
    COMMIT;

PARA VALIDAR EL:

SP_ConsularParticipantesCapacitacion:


     ========================================================================================
       BLOQUE 0: VARIABLES DE DIAGNÓSTICO Y CONTEXTO
       ======================================================================================== 
    
     Variable para almacenar el conteo de alumnos (Dependencias críticas) 
    DECLARE v_Total_Alumnos INT DEFAULT 0; 
    
     Variable para almacenar el Folio y mostrarlo en el mensaje de éxito 
    DECLARE v_Folio VARCHAR(50);
    
     Bandera de existencia para el bloqueo pesimista 
    DECLARE v_Existe INT DEFAULT NULL;

	 ========================================================================================
       BLOQUE 1: HANDLERS DE EMERGENCIA (THE SAFETY NET)
       Propósito: Capturar errores nativos del motor InnoDB y darles un tratamiento humano.
       ======================================================================================== 
    
     [1.1] Handler para Error 1451 (Cannot delete or update a parent row: a foreign key constraint fails)
       Este es el cinturón de seguridad de la base de datos. Si nuestra validación lógica (Bloque 4) 
       fallara o si se agregaran nuevas tablas en el futuro sin actualizar este SP, el motor de BD 
       bloqueará el borrado. Este handler captura ese evento, deshace la transacción y da feedback. 
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN 
        ROLLBACK; -- Crucial: Liberar cualquier lock adquirido.
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE SISTEMA [1451]: Integridad Referencial Estricta detectada. La base de datos impidió la eliminación física porque existen vínculos en tablas del sistema (FK) no contempladas en la validación de negocio.'; 
    END;

     [1.2] Handler Genérico (Catch-All Exception)
       Objetivo: Capturar cualquier anomalía técnica (disco lleno, pérdida de conexión, etc.). 
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; -- Reenvía el error original para ser logueado por el Backend.
    END;

	 ========================================================================================
       BLOQUE 2: PROTOCOLO DE VALIDACIÓN PREVIA (FAIL FAST)
       Propósito: Identificar peticiones inválidas antes de comprometer recursos de servidor.
       ======================================================================================== 
    
     2.1 Validación de Tipado e Integridad de Entrada:
       Un ID nulo o negativo es una anomalía de la aplicación cliente que no debe procesarse. 
    IF _Id_Capacitacion IS NULL OR _Id_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El Identificador de Capacitación proporcionado es inválido o nulo.';
    END IF;
    
     ========================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO DE SEGURIDAD
       ======================================================================================== 
    START TRANSACTION;

     ----------------------------------------------------------------------------------------
       PASO 3.1: VERIFICACIÓN DE EXISTENCIA Y BLOQUEO (FOR UPDATE)
       
       Objetivo: "Secuestrar" el registro padre (`Capacitaciones`).
       Efecto: Nadie puede inscribir alumnos, editar versiones o cambiar estatus de este curso
       mientras nosotros realizamos el análisis forense de eliminación.
       ---------------------------------------------------------------------------------------- 
    SELECT 1, `Numero_Capacitacion` 
    INTO v_Existe, v_Folio
    FROM `Capacitaciones`
    WHERE `Id_Capacitacion` = _Id_Capacitacion
    FOR UPDATE;

     Validación 404 
    IF v_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El curso que intenta eliminar no existe o ya fue borrado.';
    END IF;

     ========================================================================================
       BLOQUE 4: EL ESCUDO DE INTEGRIDAD (VALIDACIÓN DE DEPENDENCIAS)
       ======================================================================================== 
    
     ----------------------------------------------------------------------------------------
       PASO 4.1: ESCANEO DE "NIETOS" (ALUMNOS/PARTICIPANTES)
       
       Lógica de Negocio:
       Buscamos si existen registros en `Capacitaciones_Participantes` (Nietos) que estén
       vinculados a cualquier `DatosCapacitaciones` (Hijos) que pertenezca a este Padre.
       
       Criterio Estricto:
       NO filtramos por estatus. Si un alumno reprobó hace 2 años en una versión archivada,
       eso cuenta como historia académica y BLOQUEA el borrado.
       ---------------------------------------------------------------------------------------- 
    SELECT COUNT(*) INTO v_Total_Alumnos
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    WHERE `DC`.`Fk_Id_Capacitacion` = _Id_Capacitacion;

     [PUNTO DE BLOQUEO]: Si el contador es mayor a 0, detenemos todo. 
    IF v_Total_Alumnos > 0 THEN
        ROLLBACK; -- Liberamos el bloqueo del padre inmediatamente.
        
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ACCIÓN DENEGADA [409]: Imposible eliminar. Existen participantes/alumnos registrados en el historial de este curso (incluso en versiones anteriores). Borrarlo destruiría su historial académico. Utilice la opción de "ARCHIVAR" en su lugar.';
    END IF;
   
   */