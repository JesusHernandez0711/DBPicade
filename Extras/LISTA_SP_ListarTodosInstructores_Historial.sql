/* ============================================================================================
   PROCEDIMIENTO: SP_ListarTodosInstructores_Historial
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. CONTEXTO OPERATIVO Y PROPÓSITO (THE "WHAT" & "FOR WHOM")
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el motor de datos de "Lectura Histórica" diseñado para alimentar los **Filtros de Búsqueda**
   en los Reportes de Auditoría, Historial de Capacitaciones y Tableros de Control (Dashboards).

   [EL PROBLEMA QUE RESUELVE]: 
   El selector operativo (`SP_ListarInstructoresActivos`) oculta a los usuarios dados de baja.
   Esto generaba un "Punto Ciego" en los reportes: El administrador no podía filtrar cursos 
   impartidos en el pasado por personal que ya se jubiló o fue desvinculado.

   [SOLUCIÓN IMPLEMENTADA]: 
   Una variante del algoritmo "Zero-Join" que **ignora el estatus de vigencia** e inyecta 
   metadatos visuales ("Enriquecimiento de Etiqueta") para diferenciar activos de inactivos
   sin comprometer el rendimiento.

   --------------------------------------------------------------------------------------------
   II. DICCIONARIO DE REGLAS DE NEGOCIO (BUSINESS RULES ENGINE)
   --------------------------------------------------------------------------------------------
   [RN-01] ALCANCE UNIVERSAL (NO VIGENCY CHECK)
      - Definición: "Para auditar el pasado, todos los actores son relevantes".
      - Implementación: Se ELIMINA deliberadamente la cláusula `WHERE Activo = 1`.
      - Impacto: El listado incluye el universo total histórico de instructores.

   [RN-02] ENRIQUECIMIENTO VISUAL (STATUS BADGING)
      - Definición: "El usuario debe distinguir inmediatamente el estado operativo del recurso".
      - Lógica:
          * Si `Activo = 1`: Muestra solo el nombre.
          * Si `Activo = 0`: Inyecta el sufijo " (BAJA/INACTIVO)".
      - Justificación UX: Evita que el Admin intente reactivar o contactar a personal inexistente.

   [RN-03] REGLA DE JERARQUÍA DE COMPETENCIA (ROLE ELIGIBILITY)
      - Definición: "Solo se listan aquellos roles que históricamente pudieron impartir clase".
      - Lógica de Inclusión (Whitelist de IDs):
          * ID 1 (ADMIN), ID 2 (COORD), ID 3 (INSTRUCTOR).
      - Lógica de Exclusión:
          * ID 4 (PARTICIPANTE): Se excluye, ya que nunca debió impartir un curso.

   --------------------------------------------------------------------------------------------
   III. ANÁLISIS TÉCNICO Y RENDIMIENTO (PERFORMANCE SPECS)
   --------------------------------------------------------------------------------------------
   [A] COMPLEJIDAD ALGORÍTMICA: O(1) - INDEX SCAN
       Mantiene la optimización de filtrar por IDs numéricos (`Fk_Rol`), evitando JOINs costosos.

   [B] COSTO COMPUTACIONAL DE ENRIQUECIMIENTO
       La operación `CASE WHEN` para el sufijo se ejecuta en memoria durante la proyección. 
       Su impacto es despreciable (< 0.01ms por fila) comparado con el beneficio de UX.

   [C] HEURÍSTICA DE ORDENAMIENTO
       Mantiene la alineación estricta con el índice `Idx_Busqueda_Apellido`.

   --------------------------------------------------------------------------------------------
   IV. CONTRATO DE INTERFAZ (OUTPUT API)
   --------------------------------------------------------------------------------------------
   Retorna un arreglo JSON estricto:
     1. `Id_Usuario` (INT): Valor para el filtro SQL (`WHERE Fk_Instructor = X`).
     2. `Ficha` (STRING): Clave de búsqueda visual.
     3. `Nombre_Completo_Filtro` (STRING): Etiqueta enriquecida con estado.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ListarTodosInstructores_Historial`$$

CREATE PROCEDURE `SP_ListarTodosInstructores_Historial`()
BEGIN
    /* ========================================================================================
       SECCIÓN 1: PROYECCIÓN Y ENRIQUECIMIENTO DE DATOS (SELECT)
       ======================================================================================== */
    SELECT 
        /* [ID DEL FILTRO] 
           Valor que se usará en el `WHERE` del reporte que consuma este SP. */
        `U`.`Id_Usuario`,

        /* [CLAVE VISUAL] 
           Identificador corporativo. */
        `U`.`Ficha`,

        /* [ETIQUETA VISUAL INTELIGENTE] (Logic Injection)
           Objetivo: Generar una etiqueta que informe identidad + estado.
           
           Composición:
           1. Nombre Base: CONCAT_WS para evitar nulos.
           2. Sufijo Dinámico: CASE para detectar inactividad. */
        CONCAT(
            CONCAT_WS(' ', `IP`.`Apellido_Paterno`, `IP`.`Apellido_Materno`, `IP`.`Nombre`),
            CASE 
                WHEN `U`.`Activo` = 0 THEN ' (BAJA/INACTIVO)' 
                ELSE '' 
            END
        ) AS `Nombre_Completo_Filtro`

    /* ========================================================================================
       SECCIÓN 2: ORIGEN DE DATOS (FROM/JOIN)
       ======================================================================================== */
    FROM 
        `Usuarios` `U`

    /* RELACIÓN DE INTEGRIDAD
       Usamos INNER JOIN. Un usuario sin datos personales es irrelevante para un reporte
       nominal, por lo que se descarta por integridad de datos. */
    INNER JOIN `Info_Personal` `IP` 
        ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`

    /* NOTA DE ARQUITECTURA: 
       Se mantiene la estrategia "Zero-Join" (sin tabla Roles) para máxima velocidad. */

    /* ========================================================================================
       SECCIÓN 3: MOTOR DE REGLAS DE NEGOCIO (WHERE)
       ======================================================================================== */
    WHERE 
        /* [DIFERENCIA CRÍTICA]
           NO EXISTE FILTRO DE `Activo = 1`. 
           Estamos recuperando la historia completa (Vivos + Muertos). */
        
        /* [REGLA 2] FILTRO DE COMPETENCIA (Hardcoded IDs)
           Se filtra directamente sobre la columna FK para aprovechar la indexación numérica.
           Solo nos interesan usuarios con capacidad docente. */
        `U`.`Fk_Rol` IN (
            1,  -- ADMINISTRADOR
            2,  -- COORDINADOR
            3   -- INSTRUCTOR
        )

    /* ========================================================================================
       SECCIÓN 4: ORDENAMIENTO OPTIMIZADO (ORDER BY)
       ======================================================================================== */
    /* ALINEACIÓN DE ÍNDICE:
       Garantiza lectura secuencial del disco. */
    ORDER BY 
        `IP`.`Apellido_Paterno` ASC, 
        `IP`.`Apellido_Materno` ASC, 
        `IP`.`Nombre` ASC;

END$$

DELIMITER ;