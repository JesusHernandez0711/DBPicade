/* ====================================================================================================
   PROCEDIMIENTO: SP_Dashboard_Top3Interanual
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Tipo de Artefacto:  Procedimiento Almacenado Analítico (Analytical SP)
   - Patrón de Diseño:   "View-Driven Analytics & Subquery Isolation" (Analítica basada en Vistas)
   - Nivel de Aislamiento: READ COMMITTED (Lectura Confirmada)
   
   2. VISIÓN DE NEGOCIO Y ARQUITECTURA (BUSINESS VALUE PROPOSITION)
   -------------------------------------------------
   Este procedimiento actúa como el "Motor de Inteligencia Operativa" del Tablero Global. 
   Su objetivo es materializar la matriz de tendencia histórica interanual, identificando 
   automáticamente los "Cursos Estrella" y mapeando su evolución en los últimos 3 años.
   
   [ARQUITECTURA DE INTEGRACIÓN PLANA]:
   A diferencia de las consultas transaccionales crudas, este SP implementa la regla de negocio
   crítica: **Consumo exclusivo de `Vista_Capacitaciones`**. Al depender de esta vista 
   (que ya aplica el patrón "Flattened Master-Detail"), el SP se desvincula de la complejidad 
   de los JOINs entre Cabecera (Capacitaciones) y Detalle (DatosCapacitaciones). Esto resuelve 
   la dependencia de la columna `Fecha_Inicio` (que originalmente vive en el detalle), 
   centralizando la lógica de lectura y garantizando que las métricas del Dashboard sean 
   100% consistentes con los reportes de exportación del Coordinador.

   3. ESTRATEGIA DE RENDIMIENTO (FORENSIC PERFORMANCE STRATEGY)
   ------------------------------------------------------------
   Implementa una "Barrera de Aislamiento Forense" (Sub-Query en cláusula IN) contra la Vista 
   Maestra. Al delimitar el universo de búsqueda primero a solo 3 identificadores (`Id_Tema`), 
   el barrido de agrupación secundaria se ejecuta de forma ultra-rápida, consumiendo 
   mínimos recursos de memoria RAM en el contenedor de MariaDB.

   4. INTERFAZ DE SALIDA (DATA CONTRACT)
   -------------------------------------
   El SP devuelve 1 tabla matricial plana optimizada para consumo en PHP (Laravel Collections):
     [Anio_Fiscal]: Eje X - Año de impartición extraído dinámicamente (Ej: 2024).
     [Tema]:        Eje Z - Categoría de agrupación / Label de la línea (Ej: "Liderazgo").
     [Total]:       Eje Y - Magnitud matemática / Altura de la gráfica en Chart.js (Ej: 45).
   ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_Dashboard_Top3Interanual`$$

CREATE PROCEDURE `SP_Dashboard_Top3Interanual`()
THIS_PROC: BEGIN

    /* ================================================================================================
       BLOQUE 1: EXTRACCIÓN VECTORIZADA Y CONSOLIDACIÓN (VIEW-DRIVEN MAIN ENGINE)
       Objetivo: Entregar la matriz de datos lista para ser consumida por la librería Chart.js.
       Arquitectura: Se abandona el acceso a tablas crudas; toda la información fluye desde la
       `Vista_Capacitaciones` garantizando la integridad de los datos reportados en toda la App.
       ================================================================================================ */
       
    SELECT 
        /* --------------------------------------------------------------------------------------------
           GRUPO A: DEFINICIÓN DE EJES ESPACIALES Y CATEGÓRICOS (CHART AXIS)
           Datos que definen las dimensiones de la gráfica (Horizontal y Leyenda).
           --------------------------------------------------------------------------------------------
           [Eje Temporal - X]: 
           Extrae dinámicamente el año usando la función nativa YEAR() aplicada sobre la columna 
           `Fecha_Inicio` (provista y pre-procesada por la Vista_Capacitaciones). Esto permite agrupar 
           toda la operación diaria en bloques anuales sólidos (Ej: Todo 2025).
           
           [Eje Categórico - Z]: 
           Recupera el nombre real del curso. Ya que la vista maestra contiene esta columna, la 
           invocamos directamente. Implementamos COALESCE como un "Fail-Safe" pasivo; si por alguna 
           falla de integridad el catálogo arroja un NULL, se inyecta 'S/T' (Sin Tema) para evitar 
           la ruptura de la estructura JSON en el Frontend (Evita la Pantalla Blanca en Laravel). 
           -------------------------------------------------------------------------------------------- */
        YEAR(`VC`.`Fecha_Inicio`) AS `Anio_Fiscal`,
        -- COALESCE(`VC`.`Nombre_Tema`, 'S/T') AS `Tema`,
        /* █ CAMBIO AQUÍ: Extraemos 'Codigo_Tema' en lugar de 'Nombre_Tema' para una UX más limpia █ */
        COALESCE(`VC`.`Codigo_Tema`, 'S/C') AS `Tema`,
        
        /* --------------------------------------------------------------------------------------------
           GRUPO B: MAGNITUD ANALÍTICA Y VOLUMETRÍA (DATA POINTS)
           Valor cuantitativo que determina la altura y fluctuación de las líneas (Eje Y).
           --------------------------------------------------------------------------------------------
           [Conteo Estricto - Y]: 
           Se cuenta específicamente la Llave Primaria de la Cabecera (`Id_Capacitacion`) presente 
           en la vista. Esto garantiza que la volumetría refleje expedientes físicos reales, 
           ignorando registros fantasma o filas vacías que pudieran colarse en la proyección.
           -------------------------------------------------------------------------------------------- */
        COUNT(`VC`.`Id_Capacitacion`) AS `Total`

    /* ------------------------------------------------------------------------------------------------
       ORIGEN DE DATOS Y AISLAMIENTO ARQUITECTÓNICO (SINGLE SOURCE OF TRUTH)
       ------------------------------------------------------------------------------------------------
       [FUENTE PRIMARIA UNIFICADA]: En lugar de ensamblar JOINs complejos, delegamos esa responsabilidad 
       a `PICADE`.`Vista_Capacitaciones` (Alias: VC). Esta vista ya contiene los cruces exactos entre 
       el Expediente, el Detalle Operativo y el Catálogo de Temas, garantizando máxima fidelidad. */
    FROM `PICADE`.`Vista_Capacitaciones` `VC`

    /* ================================================================================================
       BLOQUE 2: BARRERAS DE AISLAMIENTO FORENSE (SUBQUERY ELITE ISOLATION)
       Objetivo: Filtrar el océano de datos de la vista para rastrear únicamente a los 3 temas líderes.
       Mecánica: Se interroga el campo `Id_Tema` (Ya expuesto por la vista unificada).
       ================================================================================================ */
    WHERE `VC`.`Id_Tema` IN (
        
        /* -----------------------------------------------------------------------------------------
           [ALGORITMO DE SELECCIÓN DE ÉLITE - BYPASS DE RESTRICCIÓN MARIADB]
           Los motores MariaDB/MySQL imponen una restricción dura: No permiten usar la cláusula 
           'LIMIT' directamente dentro de una subconsulta anidada en un 'IN()'. 
           Para burlar esta limitación técnica y mantener el rendimiento, envolvemos la lógica de 
           cálculo en una tabla derivada virtual (In-Memory Temporary Table) bautizada como `TopTemas`.
           
           Esta subconsulta lee la misma vista, filtra por los últimos 3 años, agrupa por tema, 
           ordena descendentemente por su popularidad total, y extrae implacablemente los 3 
           identificadores victoriosos (`Id_Tema`).
           ----------------------------------------------------------------------------------------- */
        SELECT `Id_Tema` FROM (
            SELECT `Id_Tema`
            FROM `PICADE`.`Vista_Capacitaciones`
            /* Regla de Negocio Crítica: Evaluar la popularidad solo en el marco de tiempo actual.
               (Ej: Si estamos en 2026, suma los cursos dados en 2024, 2025 y 2026). */
            WHERE YEAR(`Fecha_Inicio`) >= YEAR(CURDATE()) - 5
            GROUP BY `Id_Tema`
            ORDER BY COUNT(*) DESC
            LIMIT 3
        ) AS `TopTemas`
    )

    /* ================================================================================================
       BLOQUE 3: VENTANA MÓVIL Y CONSOLIDACIÓN FINAL (ROLLING WINDOW & MATRIX GROUPING)
       Objetivo: Asegurar la congruencia temporal en los ejes y empaquetar la matriz para PHP.
       ================================================================================================ */
       
    /* [Cortafuegos Temporal - The Rolling Window]: 
       Una vez que sabemos cuáles son los 3 temas históricos campeones, debemos garantizar que 
       solo extraemos su información de los últimos 3 años (y no su historial de hace 10 años).
       El uso de `CURDATE() - 2` automatiza el mantenimiento: el primero de enero de cada nuevo año, 
       el sistema desplazará su ventana de análisis sin intervención de un desarrollador. */
    AND YEAR(`VC`.`Fecha_Inicio`) >= YEAR(CURDATE()) - 5
    
    /* [Matriz de Intersección Dimensional]: 
       Cruza el Año (Eje X) con el Tema (Eje Z). Esta directiva `GROUP BY` es la que permite que el 
       Controlador de Laravel agrupe limpiamente las iteraciones en 3 arreglos independientes 
       para pasarlos a la propiedad `datasets` de Chart.js. */
    GROUP BY `Anio_Fiscal`, `Tema`
    
    /* [Ordenamiento de Experiencia de Usuario (UX)]: 
       Es absolutamente obligatorio ordenar el `Anio_Fiscal` de forma Ascendente (ASC). Esto fuerza a 
       que el primer dato entregado sea el año más antiguo y el último sea el año actual. 
       Esto asegura que la gráfica de líneas fluya cronológicamente de izquierda a derecha en la pantalla. */
    ORDER BY `Anio_Fiscal` ASC, `Tema` ASC;

END$$

DELIMITER ;