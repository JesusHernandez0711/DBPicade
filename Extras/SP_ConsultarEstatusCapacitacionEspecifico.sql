/* ============================================================================================
   SECCIÓN: CONSULTAS ESPECÍFICAS (PARA EDICIÓN / DETALLE)
   ============================================================================================
   Estas rutinas son clave para la UX. No solo devuelven el dato pedido, sino todo el 
   contexto necesario para que el formulario de edición se autocomplete correctamente.
   ============================================================================================ */

/* ============================================================================================
   PROCEDIMIENTO: SP_ConsultarEstatusCapacitacionEspecifico
   ============================================================================================
   
   --------------------------------------------------------------------------------------------
   I. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Es el endpoint de lectura de alta fidelidad para recuperar la "Ficha Técnica" de un Estatus 
   de Capacitación específico, identificado por su llave primaria (`Id_CatEstCap`).

   [PARA QUÉ SE USA (CONTEXTO DE UI)]:
   A) PRECARGA DE FORMULARIO DE EDICIÓN (UPDATE):
      - Cuando el administrador va a modificar un estatus (ej: cambiar la regla de bloqueo), 
        el formulario debe "hidratarse" con los datos exactos que residen en la base de datos.
      - Requisito Crítico: La fidelidad del dato. Los valores se entregan crudos (Raw Data) 
        para que los inputs del HTML reflejen la realidad sin transformaciones cosméticas.

   B) VISUALIZACIÓN DE DETALLE (AUDITORÍA):
      - Permite visualizar metadatos de auditoría (`created_at`, `updated_at`) y configuración 
        lógica profunda (`Es_Final`) que suele estar oculta en el listado general.

   --------------------------------------------------------------------------------------------
   II. ARQUITECTURA DE DATOS (DIRECT TABLE ACCESS)
   --------------------------------------------------------------------------------------------
   Este procedimiento consulta directamente la tabla física `Cat_Estatus_Capacitacion`.
   
   [JUSTIFICACIÓN TÉCNICA]:
   - Desacoplamiento de Presentación: A diferencia de las Vistas (que formatean datos para lectura 
     humana), este SP prepara los datos para el consumo del sistema (Binding de Modelos).
   - Performance: El acceso por Primary Key (`Id_CatEstCap`) tiene un costo computacional de O(1), 
     garantizando una respuesta instantánea (<1ms).

   --------------------------------------------------------------------------------------------
   III. ESTRATEGIA DE SEGURIDAD (DEFENSIVE PROGRAMMING)
   --------------------------------------------------------------------------------------------
   - Validación de Entrada: Se rechazan IDs nulos o negativos antes de tocar el disco.
   - Fail Fast (Fallo Rápido): Se verifica la existencia del registro antes de intentar devolver datos. 
     Esto permite diferenciar claramente entre un "Error 404" (Recurso no encontrado) y un 
     "Error 500" (Fallo de servidor).

   --------------------------------------------------------------------------------------------
   IV. VISIBILIDAD (SCOPE)
   --------------------------------------------------------------------------------------------
   - NO se filtra por `Activo = 1`.
   - Razón: Un estatus puede estar "Desactivado" (Baja Lógica). El administrador necesita poder 
     consultarlo para ver su configuración y decidir si lo Reactiva.

   --------------------------------------------------------------------------------------------
   V. DICCIONARIO DE DATOS (OUTPUT CONTRACT)
   --------------------------------------------------------------------------------------------
   Retorna una única fila (Single Row) mapeada semánticamente:
      - [Id_Estatus]: Llave primaria.
      - [Codigo_Estatus]: Clave corta técnica.
      - [Nombre_Estatus]: Etiqueta humana.
      - [Descripcion_Estatus]: Contexto.
      - [Bandera_de_Bloqueo]: Alias de negocio para `Es_Final` (0=Bloquea, 1=Libera).
      - [Estatus]: Alias de negocio para `Activo` (1=Vigente, 0=Baja).
      - [Auditoría]: Fechas de creación y modificación.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarEstatusCapacitacionEspecifico`$$

CREATE PROCEDURE `SP_ConsultarEstatusCapacitacionEspecifico`(
    IN _Id_Estatus INT -- [OBLIGATORIO] Identificador único del Estatus a consultar
)
BEGIN
    /* ========================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Objetivo: Asegurar que el parámetro recibido sea un entero positivo válido.
       Evita cargas innecesarias al motor de base de datos con peticiones basura.
       ======================================================================================== */
    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El Identificador del Estatus es inválido (Debe ser un entero positivo).';
    END IF;

    /* ========================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA (FAIL FAST STRATEGY)
       Objetivo: Validar que el recurso realmente exista en la base de datos.
       
       NOTA DE IMPLEMENTACIÓN:
       Usamos `SELECT 1` que es más ligero que seleccionar columnas reales, ya que solo 
       necesitamos confirmar la presencia de la llave en el índice primario.
       ======================================================================================== */
    IF NOT EXISTS (SELECT 1 FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = _Id_Estatus) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Estatus de Capacitación solicitado no existe o fue eliminado físicamente.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: CONSULTA PRINCIPAL (DATA RETRIEVAL)
       Objetivo: Retornar el objeto de datos completo y puro (Raw Data) con alias semánticos.
       ======================================================================================== */
    SELECT 
        /* --- GRUPO A: IDENTIDAD DEL REGISTRO --- */
        /* Este ID es la llave primaria inmutable. */
        `Id_CatEstCap`   AS `Id_Estatus`,
        
        /* --- GRUPO B: DATOS EDITABLES --- */
        /* El Frontend usará estos campos para llenar los inputs de texto. */
        `Codigo`         AS `Codigo_Estatus`,
        `Nombre`         AS `Nombre_Estatus`,
        `Descripcion`    AS `Descripcion_Estatus`,
        
        /* --- GRUPO C: LÓGICA DE NEGOCIO (CORE LOGIC) --- */
        /* [IMPORTANTE]: Este campo define el comportamiento de los Killswitches.
           Alias: `Bandera_de_Bloqueo` 
           Valor 0 = El proceso está vivo (Bloquea eliminación de temas/usuarios).
           Valor 1 = El proceso terminó (Libera recursos). */
        `Es_Final`       AS `Bandera_de_Bloqueo`,

        /* --- GRUPO D: METADATOS DE CONTROL DE CICLO DE VIDA --- */
        /* Este valor (0 o 1) indica si el estatus es utilizable actualmente en nuevos registros.
           1 = Activo/Visible, 0 = Inactivo/Oculto (Baja Lógica). */
        `Activo`         AS `Estatus`,        
        
        /* --- GRUPO E: AUDITORÍA DE SISTEMA --- */
        /* Fechas útiles para mostrar en el pie de página del modal de detalle o tooltip. */
        `created_at`     AS `Fecha_Registro`,
        `updated_at`     AS `Ultima_Modificacion`
        
    FROM `Cat_Estatus_Capacitacion`
    WHERE `Id_CatEstCap` = _Id_Estatus
    LIMIT 1; /* Buena práctica: Asegura al optimizador que se detenga tras el primer hallazgo. */

END$$

DELIMITER ;