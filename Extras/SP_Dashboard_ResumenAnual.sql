/* ====================================================================================================
   PROCEDIMIENTO: SP_Dashboard_ResumenAnual_
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Nombre: SP_Dashboard_ResumenAnual
   - Tipo: Motor de Analítica Agrupada (Aggregated Analytics Engine)
   - Nivel de Aislamiento: Read Uncommitted (Para máxima velocidad en Dashboards)
   - Complejidad Computacional: O(N) optimizada por índices primarios.
   
   2. VISIÓN DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------
   Este procedimiento es el corazón del **Tablero de Control Estratégico** (Dashboard).
   Su misión es transformar miles de registros operativos dispersos en **Indicadores Clave de Desempeño (KPIs)**
   agrupados por Año Fiscal.
   
   Alimenta las "Tarjetas Anuales" que permiten al Coordinador responder en 1 segundo:
     - "¿Cuál fue el volumen de operación del año pasado?"
     - "¿Qué tan eficientes fuimos?" (Finalizados vs Cancelados).
     - "¿A cuántas personas impactamos?" (Cobertura).

   3. ESTRATEGIA TÉCNICA: "HARDCODED ID OPTIMIZATION"
   --------------------------------------------------
   Para garantizar una renderización instantánea del Dashboard (< 100ms), eliminamos los JOINs 
   hacia catálogos de texto (`Cat_Estatus`) y utilizamos comparaciones numéricas directas.
   
   [MAPEO DE IDs DE ESTATUS CRÍTICOS]:
     - ID 4  = FINALIZADO (Éxito Operativo).
     - ID 8  = CANCELADO (Fallo Operativo).
     - ID 10 = CERRADO/ARCHIVADO (Cierre Administrativo).
     - RESTO = EN PROCESO (Operación Viva: Programado, En Curso, Por Iniciar, etc.).

   4. INTEGRIDAD DE DATOS: "LATEST SNAPSHOT STRATEGY"
   --------------------------------------------------
   Utiliza una subconsulta de `MAX(Id)` para asegurar que solo se contabilice la **última versión** de cada curso. Esto evita la duplicidad estadística si un curso fue editado 20 veces.

   ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_Dashboard_ResumenAnual`$$

CREATE PROCEDURE `SP_Dashboard_ResumenAnual`()
BEGIN
    /* ============================================================================================
       BLOQUE ÚNICO: CONSULTA ANALÍTICA MAESTRA
       No requiere parámetros. Escanea toda la historia y la agrupa por años.
       ============================================================================================ */
    SELECT 
        /* ----------------------------------------------------------------------------------------
           DIMENSIÓN TEMPORAL (AGRUPADOR PRINCIPAL)
           Define el "Contenedor" de la tarjeta (Ej: Tarjeta 2026, Tarjeta 2025).
           ---------------------------------------------------------------------------------------- */
        YEAR(`DC`.`Fecha_Inicio`)          AS `Anio_Fiscal`,
        
        /* ----------------------------------------------------------------------------------------
           KPI DE VOLUMEN (TOTAL THROUGHPUT)
           Total de folios únicos gestionados en el año, sin importar su destino final.
           ---------------------------------------------------------------------------------------- */
        COUNT(DISTINCT `Cap`.`Numero_Capacitacion`) AS `Total_Cursos_Gestionados`,
        
        /* ----------------------------------------------------------------------------------------
           KPIs DE SALUD OPERATIVA (BREAKDOWN BY STATUS ID)
           Desglose basado en reglas de negocio estrictas usando IDs fijos para velocidad.
           ---------------------------------------------------------------------------------------- */
        
        /* [KPI ÉXITO]: Cursos que concluyeron satisfactoriamente (ID 4) */
		/* [KPI ÉXITO CORREGIDO]: 
           Suma Finalizados (4) Y Archivados (10).
           Lógica: Si está archivado, es porque se finalizó correctamente. */
        SUM(CASE 
            WHEN `DC`.`Fk_Id_CatEstCap` IN (4, 10) THEN 1 
            ELSE 0 
        END) AS `Finalizados`,
        
        /* [KPI FALLO]: Cursos que se cancelaron y no ocurrieron (ID 8) */
        SUM(CASE 
            WHEN `DC`.`Fk_Id_CatEstCap` = 8 THEN 1 
            ELSE 0 
        END) AS `Cursos_Cancelados`,
        
        /* [KPI VIVO]: Cursos en cualquier etapa de ejecución o planeación.
           Lógica: Todo lo que NO sea Final(4), Cancelado(8) o Archivado(10). */
        SUM(CASE 
            WHEN `DC`.`Fk_Id_CatEstCap` NOT IN (4, 8, 10) THEN 1 
            ELSE 0 
        END) AS `Cursos_En_Proceso`,

        /* ----------------------------------------------------------------------------------------
           KPIs DE GESTIÓN ADMINISTRATIVA
           ---------------------------------------------------------------------------------------- */
        /* [KPI ARCHIVO]: Expedientes cerrados. 
           Suma:
             1. Cursos apagados globalmente (`Cap.Activo = 0`).
             2. Cursos marcados explícitamente con estatus "Cerrado/Archivado" (ID 10). */
        SUM(CASE 
            WHEN `Cap`.`Activo` = 0 OR `DC`.`Fk_Id_CatEstCap` = 10 THEN 1 
            ELSE 0 
        END) AS `Expedientes_Archivados`,
        
        /* ----------------------------------------------------------------------------------------
           KPIs DE IMPACTO (COBERTURA)
           ---------------------------------------------------------------------------------------- */
        /* Suma de personas reales que tomaron los cursos. */
        SUM(`DC`.`AsistentesReales`)       AS `Total_Personas_Capacitadas`,
        
        /* ----------------------------------------------------------------------------------------
           METADATA DE ACTUALIDAD
           ---------------------------------------------------------------------------------------- */
        /* Fecha del curso más lejano en el calendario para ese año. */
        MAX(`DC`.`Fecha_Fin`)              AS `Ultima_Actividad`

    FROM `Picade`.`DatosCapacitaciones` `DC` -- Tabla Operativa (Hijo)
    
    /* JOIN con el Padre (Necesario para agrupar por Folio Único y ver el Soft Delete Global) */
    INNER JOIN `Picade`.`Capacitaciones` `Cap` 
        ON `DC`.`Fk_Id_Capacitacion` = `Cap`.`Id_Capacitacion`
    
    /* --------------------------------------------------------------------------------------------
       FILTRO DE UNICIDAD E INTEGRIDAD (LATEST SNAPSHOT STRATEGY)
       Esta es la cláusula más crítica del reporte.
       
       PROBLEMA: Un curso puede tener 50 versiones históricas (Instructor A, luego B, luego C...).
       Si sumamos todo, triplicaríamos los números.
       
       SOLUCIÓN: Hacemos INNER JOIN con una subconsulta que extrae el MAX(ID) de cada Padre.
       EFECTO: Solo pasa a la suma la "Última Foto" conocida de cada curso.
       -------------------------------------------------------------------------------------------- */
    INNER JOIN (
        SELECT MAX(`Id_DatosCap`) as `MaxId` 
        FROM `Picade`.`DatosCapacitaciones` 
        GROUP BY `Fk_Id_Capacitacion`
    ) `Latest` ON `DC`.`Id_DatosCap` = `Latest`.`MaxId`

    /* Agrupamiento temporal */
    GROUP BY YEAR(`DC`.`Fecha_Inicio`)
    
    /* Ordenamiento: El año más reciente (futuro o presente) aparece primero */
    ORDER BY `Anio_Fiscal` DESC;

END$$

DELIMITER ;