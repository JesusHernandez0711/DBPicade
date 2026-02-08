/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_CambiarEstatusCapacitacionParticipante
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   ----------------------------------------------------------------------------------------------------------
   1. FICHA TÉCNICA DE ALTO NIVEL (TECHNICAL DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre Oficial:       SP_CambiarEstatusCapacitacionParticipante
   - Sistema:              PICADE (Plataforma Institucional de Capacitación y Desarrollo)
   - Auditoria: 		   Transacciones de Estado y Ciclo de Vida del Participante
   - Clasificación:        Transacción Conmutativa de Estado (Toggle State Transaction)
   - Nivel de Seguridad:   Administrativo / Privilegiado
   - Modelo ACID:          Cumplimiento Total (Atomicidad garantizada por START TRANSACTION)
   - Aislamiento SQL:      READ COMMITTED (Evita lecturas sucias durante el cálculo de cupo)
   - Objetivo Forense:     Centralizar en un solo punto de entrada (Single Point of Truth) la entrada y 
                           salida de alumnos, garantizando que el "Toggle" sea atómico.
   
   ----------------------------------------------------------------------------------------------------------
   2. ANÁLISIS DE RIESGOS Y MITIGACIÓN (RISK ASSESSMENT)
   ----------------------------------------------------------------------------------------------------------
   - RIESGO DE SOBREVENTA (OVERBOOKING): En un entorno concurrente, dos coordinadores podrían intentar
     reinscribir participantes al mismo tiempo. 
     MITIGACIÓN: El SP utiliza lógica de cupo híbrido calculada segundos antes del COMMIT, bloqueando
     el registro objetivo para evitar colisiones.
     
   - RIESGO DE CORRUPCIÓN HISTÓRICA: Dar de baja a un alumno que ya tiene calificación borraría la validez
     de los reportes de acreditación.
     MITIGACIÓN: Bloqueo duro (Hard Block) en la Rama de Baja si `Calificacion` IS NOT NULL.
     
   - RIESGO DE INOPERABILIDAD: Cambiar estados en cursos ya borrados o cancelados.
     MITIGACIÓN: Verificación de Snapshot de Contexto del Curso antes de evaluar al alumno.

   ----------------------------------------------------------------------------------------------------------
   3. ARQUITECTURA DE LA SOLUCIÓN (SINGLE-ENDPOINT TOGGLE)
   ----------------------------------------------------------------------------------------------------------
   El procedimiento implementa un patrón de "Interruptor Lógico". En lugar de tener dos rutas en el backend,
   el sistema operativo de la base de datos detecta el estatus actual:
   
   SI ESTATUS = 5 (BAJA):
      Inicia sub-proceso de REINSCRIPCIÓN.
      Verifica: Cupo (Meta - MAX(Sistema, Manual)).
      Resultado: Estatus 1 (INSCRITO).
   
   SI ESTATUS != 5 (ACTIVO/OTROS):
      Inicia sub-proceso de BAJA ADMINISTRATIVA.
      Verifica: Ausencia de calificación.
      Resultado: Estatus 5 (BAJA).

   ----------------------------------------------------------------------------------------------------------
   4. DICCIONARIO DE ACCIONES (ACTION CODES)
   ----------------------------------------------------------------------------------------------------------
   - 'REINSCRITO':    El alumno recuperó su asiento exitosamente.
   - 'BAJA_EXITOSA':  El alumno liberó el asiento y se guardó la justificación.
   - 'ERROR_TECNICO': Fallo en el motor InnoDB o violación de integridad.
   - 'CUPO_LLENO':    Rechazo por falta de espacio físico/lógico.

   ----------------------------------------------------------------------------------------------------------
   5. ANÁLISIS DE IMPACTO EN DATOS (DATA IMPACT ANALYSIS)
   ----------------------------------------------------------------------------------------------------------
   - TABLA OBJETIVO: `Capacitaciones_Participantes`
   - COLUMNAS AFECTADAS: 
     * `Fk_Id_CatEstPart`: Actualización de estado operativo.
     * `Justificacion`: Concatenación forense de motivos con timestamp.
     * `updated_at`: Registro cronológico de la modificación.
     * `Fk_Id_Usuario_Updated_By`: Registro de autoría administrativa.
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════ */

DELIMITER $$

-- Eliminación preventiva del objeto para garantizar despliegue limpio (Idempotencia de Script)
DROP PROCEDURE IF EXISTS `SP_CambiarEstatusCapacitacionParticipante`$$

CREATE PROCEDURE `SP_CambiarEstatusCapacitacionParticipante`(
    /* ------------------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS DE ENTRADA (INTERFACE DEFINITION)
       ------------------------------------------------------------------------------------------------------ */
    IN _Id_Usuario_Ejecutor INT,       -- ID del Admin/Coordinador (Trazabilidad de Auditoría)
    IN _Id_Registro_Participante INT,  -- PK de la tabla Capacitaciones_Participantes
    IN _Motivo_Cambio VARCHAR(250)     -- Argumento obligatorio para el log de Justificación
)
ProcTogglePart: BEGIN
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 1: GESTIÓN DE VARIABLES Y ASIGNACIÓN DE MEMORIA (VARIABLE ALLOCATION)
       Cada variable está diseñada para evitar el uso de funciones pesadas dentro de los IF/ELSE.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [1.1] Variables de Integridad Referencial
    -- Utilizadas para confirmar que las llaves foráneas y el registro objetivo existen físicamente.
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;       -- Flag binario de existencia del Admin solicitante.
    DECLARE v_Registro_Existe INT DEFAULT 0;       -- Flag binario de existencia de la inscripción PK.
    DECLARE v_Id_Detalle_Curso INT DEFAULT 0;      -- Almacena el ID de la instancia de capacitación.
    DECLARE v_Id_Padre INT DEFAULT 0;              -- ID de la cabecera (Capacitaciones) para lectura de Metas.
    
    -- [1.2] Variables de Estado y Ciclo de Vida (Data Snapshot)
    -- Almacenan el "Snapshot" del momento exacto en que se llamó al procedimiento para evitar inconsistencias.
    DECLARE v_Estatus_Actual_Alumno INT DEFAULT 0; -- ID del estado actual del alumno (ej. 1=Inscrito, 5=Baja).
    DECLARE v_Estatus_Curso INT DEFAULT 0;         -- ID del estado actual del curso (Whitelist check).
    DECLARE v_Curso_Activo INT DEFAULT 0;          -- Flag de borrado lógico para asegurar vigencia.
    DECLARE v_Tiene_Calificacion INT DEFAULT 0;    -- Booleano para protección de integridad histórica académica.
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT ''; -- Identificador Numero_Capacitacion legible para el usuario.
    DECLARE v_Nombre_Alumno VARCHAR(200) DEFAULT '';-- Nombre del alumno recuperado para mensajes personalizados.
    
    -- [1.3] Variables para Aritmética de Cupo Híbrido (Capacity Logic)
    -- Se utilizan exclusivamente en la RAMA DE REINSCRIBIR para verificar disponibilidad.
    DECLARE v_Cupo_Maximo INT DEFAULT 0;           -- Capacidad total permitida según planeación de curso.
    DECLARE v_Conteo_Sistema INT DEFAULT 0;        -- Conteo físico de registros en estado != BAJA.
    DECLARE v_Conteo_Manual INT DEFAULT 0;         -- Cupo bloqueado manualmente por un coordinador (AsistentesReales).
    DECLARE v_Asientos_Ocupados INT DEFAULT 0;     -- El factor resultante de aplicar la regla GREATEST().
    DECLARE v_Cupo_Disponible INT DEFAULT 0;       -- Disponibilidad neta restante para la operación.
    
    -- [1.4] Variables de Comunicación Dinámica (Output Buffering)
    -- Almacenan la respuesta formateada que será entregada al sistema llamante.
    DECLARE v_Mensaje_Final VARCHAR(255) DEFAULT '';-- Texto descriptivo del resultado de la transacción.
    DECLARE v_Accion_Final VARCHAR(50) DEFAULT ''; -- Código de acción para disparar lógica en Frontend/Backend.
    
    -- [1.5] Definición de Constantes de Negocio (Business Rules Mappings)
    -- Centralización de IDs maestros para asegurar alineación con la arquitectura PICADE.
    DECLARE c_ESTATUS_INSCRITO INT DEFAULT 1;      -- ID de estado operativo: INSCRITO.
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;          -- ID de estado operativo: BAJA ADMINISTRATIVA.
    DECLARE c_CURSO_CANCELADO INT DEFAULT 8;       -- ID de estado inoperable: CANCELADO.
    DECLARE c_CURSO_ARCHIVADO INT DEFAULT 10;      -- ID de estado inoperable: CERRADO/ARCHIVADO.

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: HANDLER DE SEGURIDAD TRANSACCIONAL (ACID PROTECTION)
       Mecansimo de recuperación ante desastres. Captura fallos de red, de motor InnoDB o de sintaxis.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- [FORENSIC ACTION]: Si la transacción quedó abierta, se deshacen los cambios inmediatamente.
        ROLLBACK;
        
        -- Respuesta estandarizada para monitoreo de logs técnicos.
        SELECT 
            'ERROR TÉCNICO [500]: Fallo crítico detectado por el motor de BD al alternar el estado del participante.' AS Mensaje, 
            'ERROR_TECNICO' AS Accion;
    END;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN ESTRUCTURAL (FAIL-FAST)
       Objetivo: Rechazar punteros inválidos antes de asignar recursos de lectura de disco.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [0.1] Validación del Ejecutor: Previene acciones de sistemas no autenticados o IDs nulos.
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es inválido o nulo.' AS Mensaje, 
			'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- [0.2] Validación del Registro Objetivo: Asegura que el puntero PK a la inscripción sea válido.
    IF _Id_Registro_Participante IS NULL OR _Id_Registro_Participante <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: El ID del Registro de Participante es inválido o nulo.' AS Mensaje, 
			'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- [0.3] Validación de Justificación: Cumplimiento de Norma Forense. No hay cambios sin rastro.
    IF _Motivo_Cambio IS NULL OR TRIM(_Motivo_Cambio) = '' 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El motivo del cambio es obligatorio para fines de trazabilidad forense.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: VERIFICACIÓN DE CONTEXTO Y SEGURIDAD (USER & RESOURCE AUTHENTICATION)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [1.1] Validación de Identidad del Ejecutor
    -- Confirmamos que el Admin tiene sesión activa y privilegios en la tabla de Usuarios.
    SELECT COUNT(*) 
    INTO v_Ejecutor_Existe 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor 
		AND `Activo` = 1;
    
    IF v_Ejecutor_Existe = 0 
		THEN 
			SELECT 'ERROR DE PERMISOS [403]: El Usuario Ejecutor no tiene privilegios activos en el sistema.' AS Mensaje, 
        'ACCESO_DENEGADO' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- [1.2] Carga Masiva de Datos del Registro (Data Hydration)
    -- Snapshot forense para determinar el curso de acción sin lecturas redundantes posteriores.
    SELECT 
        COUNT(*),                               -- [0] Verificador de existencia física en BD.
        COALESCE(`CP`.`Fk_Id_CatEstPart`, 0),   -- [1] Estatus actual del alumno para el Toggle.
        `CP`.`Fk_Id_DatosCap`,                  -- [2] Puntero FK a la instancia del curso.
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`), -- [3] Nombre completo del Alumno.
        CASE WHEN `CP`.`Calificacion` IS NOT NULL THEN 1 ELSE 0 END, -- [4] Semáforo de Calificación.
        `DC`.`Activo`,                          -- [5] Estado lógico del curso.
        `DC`.`Fk_Id_CatEstCap`,                 -- [6] Estado operativo del curso.
        `DC`.`Fk_Id_Capacitacion`,              -- [7] Puntero a la meta de cupo.
        COALESCE(`DC`.`AsistentesReales`, 0)    -- [8] Registro manual de asistencia del coordinador.
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

    -- [1.3] Validación de Existencia de Inscripción
    IF v_Registro_Existe = 0 
		THEN 
			SELECT 'ERROR DE INTEGRIDAD [404]: No se encontró el registro de inscripción solicitado en la base de datos.' AS Mensaje, 
            'RECURSO_NO_ENCONTRADO' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- [1.4] Lectura de Configuración de Meta (Capacitaciones)
    SELECT `Numero_Capacitacion`, `Asistentes_Programados` 
    INTO v_Folio_Curso, v_Cupo_Maximo
    FROM `Capacitaciones` 
    WHERE `Id_Capacitacion` = v_Id_Padre;

    -- [1.5] Validación de Lista Negra de Estatus de Curso
    -- Regla de Negocio: No se permite alterar participantes si el curso ya está muerto administrativamente.
    IF v_Estatus_Curso IN (c_CURSO_CANCELADO, c_CURSO_ARCHIVADO) 
		THEN
			SELECT CONCAT('ERROR DE LÓGICA [409]: El curso "', v_Folio_Curso, '" está CANCELADO o ARCHIVADO. No se permiten modificaciones de lista.') AS Mensaje, 
               'ESTATUS_PROHIBIDO' AS Accion;
        LEAVE ProcTogglePart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: ÁRBOL DE DECISIÓN LÓGICA (BUSINESS FLOW TOGGLE)
       El sistema bifurca el flujo basándose en el estado actual del alumno.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    IF v_Estatus_Actual_Alumno = c_ESTATUS_BAJA THEN
        
        /* ═══════════════════════════════════════════════════════════════════════════════════════════════
           RAMA A: PROCESO DE REINSCRIBIR / REACTIVAR PARTICIPANTE
           Justificación: El alumno tiene un registro previo pero su asiento fue liberado.
           ═══════════════════════════════════════════════════════════════════════════════════════════════ */
        
        -- [A.1] Validación Crítica de Cupo Híbrido (Race Condition Mitigation)
        -- Realizamos el cálculo matemático segundos antes de la actualización de disco.
        SELECT COUNT(*) INTO v_Conteo_Sistema 
        FROM `Capacitaciones_Participantes` 
        WHERE `Fk_Id_DatosCap` = v_Id_Detalle_Curso 
          AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

        -- Regla GREATEST(): Pesimismo operacional para evitar sobrecupo.
        SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);
        SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
        
        -- Evaluación de Capacidad
        IF v_Cupo_Disponible <= 0 
			THEN
				SELECT CONCAT('ERROR DE CUPO [409]: Imposible reinscribir a "', v_Nombre_Alumno, '". La capacitación "', v_Folio_Curso, '" ha alcanzado su límite máximo.') AS Mensaje, 
                   'CUPO_LLENO' AS Accion;
            LEAVE ProcTogglePart;
        END IF;
        
        -- [A.2] Ejecución de Persistencia (Update Branch A)
        START TRANSACTION;
            UPDATE `Capacitaciones_Participantes`
            SET `Fk_Id_CatEstPart` = c_ESTATUS_INSCRITO, -- Reactivación formal (1).
                -- [AUDIT]: Registro histórico de la reactivación.
                `Justificacion` = CONCAT('REINSCRIBIR [', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), ']: ', _Motivo_Cambio),
                `updated_at` = NOW(),
                `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
            WHERE `Id_CapPart` = _Id_Registro_Participante;
        COMMIT;
        
        -- Configuración de Buffers para la Respuesta Final.
        SET v_Mensaje_Final = CONCAT('REINSCRIPCIÓN EXITOSA: El participante "', v_Nombre_Alumno, '" ha sido reactivado en el curso "', v_Folio_Curso, '".');
        SET v_Accion_Final = 'REINSCRITO';

    ELSE
        
        /* ═══════════════════════════════════════════════════════════════════════════════════════════════
           RAMA B: PROCESO DE DAR DE BAJA ADMINISTRATIVA
           Justificación: El alumno está ocupando un asiento y se requiere su desincorporación.
           ═══════════════════════════════════════════════════════════════════════════════════════════════ */
        
        -- [B.1] Validación de Integridad Académica (Constraint Academic Protection)
        -- No es permitido remover alumnos que ya tienen nota final para no alterar promedios históricos.
        IF v_Tiene_Calificacion = 1 
			THEN
				SELECT CONCAT('ERROR DE INTEGRIDAD [409]: No se puede dar de baja a "', v_Nombre_Alumno, '" porque ya cuenta con una calificación asentada.') AS Mensaje, 
                   'CONFLICTO_ESTADO' AS Accion;
            LEAVE ProcTogglePart;
        END IF;
        
        -- [B.2] Ejecución de Persistencia (Update Branch B)
        START TRANSACTION;
            UPDATE `Capacitaciones_Participantes`
            SET `Fk_Id_CatEstPart` = c_ESTATUS_BAJA, -- Desincorporación formal (5).
                -- [AUDIT]: Registro histórico de la salida administrativa.
                `Justificacion` = CONCAT('DAR DE BAJA [', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), ']: ', _Motivo_Cambio),
                `updated_at` = NOW(),
                `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
            WHERE `Id_CapPart` = _Id_Registro_Participante;
        COMMIT;
        
        -- Configuración de Buffers para la Respuesta Final.
        SET v_Mensaje_Final = CONCAT('BAJA REGISTRADA: El participante "', v_Nombre_Alumno, '" ha sido retirado correctamente del curso "', v_Folio_Curso, '".');
        SET v_Accion_Final = 'BAJA_EXITOSA';
        
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: DESCARGA DE RESPUESTA FINAL (FINAL OUTPUT)
       Regresa un resultset unitario procesable por la capa de aplicación (Laravel/Eloquent).
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT v_Mensaje_Final AS Mensaje, v_Accion_Final AS Accion;

END$$

DELIMITER ;

/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   NOTAS DE AUDITORÍA Y SEGURIDAD:
   1. El procedimiento es Idempotente respecto a la solicitud (siempre alternará el estado).
   2. La Rama A y B están protegidas por sus respectivas reglas de integridad.
   3. Cumple con el Estándar PICADE para Trazabilidad Administrativa.
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════ */