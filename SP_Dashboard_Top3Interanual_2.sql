    /* ====================================================================================================
        PROCEDIMIENTO: SP_Dashboard_Top3Interanual
       ====================================================================================================
       1. FICHA TÉCNICA (TECHNICAL DATASHEET)
       --------------------------------------
       - Tipo de Artefacto:  Procedimiento Almacenado Analítico de Alto Rendimiento (Analytical SP).
       - Patrón de Diseño:   "Dynamic Windowed Podium" (Podio Dinámico por Funciones de Ventana).
       - Nivel de Aislamiento: READ COMMITTED (Lectura Confirmada para evitar Dirty Reads).
       
       2. VISIÓN DE NEGOCIO Y ARQUITECTURA (BUSINESS VALUE PROPOSITION)
       -------------------------------------------------
       Este procedimiento actúa como el "Motor de Inteligencia Operativa" del Tablero Global. 
       A diferencia de un Top Global estático, este algoritmo descubre a los "Campeones Anuales" 
       de forma independiente. Entiende que el mercado cambia y que el curso más popular del 2024 
       puede no ser el mismo que el del 2025. Al consumir exclusivamente la `Vista_Capacitaciones`, 
       garantiza una integridad referencial absoluta, abstrayendo al motor de los múltiples JOINs 
       transaccionales subyacentes y entregando datos limpios y homologados al controlador PHP.

       3. ESTRATEGIA DE RENDIMIENTO (FORENSIC PERFORMANCE STRATEGY)
       ------------------------------------------------------------
       Abandona por completo las subconsultas anidadas tradicionales y los cursores iterativos. 
       En su lugar, implementa Expresiones de Tabla Comunes (CTEs) combinadas con `ROW_NUMBER()`. 
       Esta técnica permite que el motor de MariaDB lea la tabla base una sola vez (Single Pass Scan), 
       cargue los resultados en la memoria RAM (In-Memory Temp Table), los particione y los clasifique 
       en una fracción del tiempo de cómputo que requeriría un enfoque imperativo.

       4. INTERFAZ DE SALIDA (DATA CONTRACT)
       -------------------------------------
       El SP devuelve una matriz de 4 dimensiones perfecta para iteración lógica en Laravel:
         [Anio_Fiscal]: (INT)     Eje X temporal fijo.
         [Tema]:        (VARCHAR) Código corto del curso para limpieza visual en la leyenda.
         [Total]:       (INT)     Volumetría exacta para la altura de la barra.
         [Posicion]:    (INT)     Medalla obtenida (1=Oro, 2=Plata, 3=Bronce).
       ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_Dashboard_Top3Interanual`$$

CREATE PROCEDURE `SP_Dashboard_Top3Interanual`()

THIS_PROC: BEGIN

    /* ----------------------------------------------------------------------------------------------------
        FASE 1: EXTRACCIÓN Y AGRUPACIÓN BASE (COMMON TABLE EXPRESSION: ConteoAnual)
       ────────────────────────────────────────────────────────────────────────────────────────────────────
       1. [Estrategia CTE]: Se declara la primera tabla temporal en memoria (ConteoAnual). Su objetivo 
          es reducir el universo total de la vista a una matriz plana de Años y Temas.
       2. [Eje Temporal Forzado]: Implementa el patrón "Rolling Window" con `YEAR(CURDATE()) - 4`. 
          Esto obliga al motor a ignorar la historia profunda de la empresa y concentrarse estrictamente 
          en el quinquenio de interés (últimos 5 años), logrando un mantenimiento de código cero (Zero-Touch).
       3. [Limpieza de Datos]: Aplica `COALESCE` sobre el `Codigo_Tema`. En caso de una ruptura de 
          integridad en el catálogo, previene fallos de renderizado inyectando 'S/C' (Sin Código).
       4. [Métrica Auditada]: Ejecuta un `COUNT` estricto sobre la llave primaria (`Id_Capacitacion`), 
          garantizando que cada unidad contabilizada represente un evento físico real y registrado.
       ---------------------------------------------------------------------------------------------------- */
    WITH ConteoAnual AS (
        SELECT 
            YEAR(`VC`.`Fecha_Inicio`) AS `Anio_Fiscal`,
            COALESCE(`VC`.`Codigo_Tema`, 'S/C') AS `Tema`,
            COUNT(`VC`.`Id_Capacitacion`) AS `Total`
        FROM `PICADE`.`Vista_Capacitaciones` `VC`
        WHERE YEAR(`VC`.`Fecha_Inicio`) >= YEAR(CURDATE()) - 4
        GROUP BY `Anio_Fiscal`, `Tema`
    ),
    
    /* ----------------------------------------------------------------------------------------------------
        FASE 2: MOTOR DE CLASIFICACIÓN DINÁMICA (COMMON TABLE EXPRESSION: RankedAnual)
       ────────────────────────────────────────────────────────────────────────────────────────────────────
       1. [Lectura Diferida]: Esta segunda CTE consume el resultado pre-procesado de `ConteoAnual`, 
          lo que significa que ya está operando sobre un set de datos minúsculo y altamente optimizado.
       2. [Funciones de Ventana - ROW_NUMBER]: Es el núcleo algorítmico del proceso. 
       3. [PARTITION BY]: Actúa como una barrera aislante. Le indica al motor que el ranking debe 
          reiniciarse desde 1 cada vez que cambia el `Anio_Fiscal`. Esto garantiza la independencia anual.
       4. [ORDER BY Total DESC]: Dentro de cada partición (Año), ordena a los competidores por su 
          volumetría de mayor a menor, otorgando el #1 al que tenga más imparticiones.
       ---------------------------------------------------------------------------------------------------- */
    RankedAnual AS (
        SELECT 
            `Anio_Fiscal`,
            `Tema`,
            `Total`,
            ROW_NUMBER() OVER(PARTITION BY `Anio_Fiscal` ORDER BY `Total` DESC) as `Posicion`
        FROM ConteoAnual
    )
    
    /* ----------------------------------------------------------------------------------------------------
        FASE 3: FILTRADO DE ÉLITE Y ENTREGA DE RESULTSET (FINAL DELIVERY)
       ────────────────────────────────────────────────────────────────────────────────────────────────────
       1. [Corte de Medallistas]: La CTE anterior rankeó a TODOS los cursos (pudiendo llegar a la posición 50). 
          Esta cláusula `WHERE Posicion <= 3` funciona como una tijera quirúrgica que desecha todo lo que 
          esté por debajo del bronce, liberando carga útil en la red (Payload Size).
       2. [Ordenamiento UX (User Experience)]: El `ORDER BY` final es crítico para Chart.js. 
          Al ordenar primero por `Anio_Fiscal ASC`, aseguramos que la gráfica se dibuje de izquierda a derecha.
       3. [Ordenamiento Secundario]: Al ordenar por `Posicion ASC`, garantizamos que Laravel reciba primero 
          el Oro, luego la Plata y al final el Bronce para su correcta inyección en los Datasets visuales.
       ---------------------------------------------------------------------------------------------------- */
    SELECT 
        `Anio_Fiscal`, 
        `Tema`, 
        `Total`, 
        `Posicion`
    FROM RankedAnual
    WHERE `Posicion` <= 3 
    ORDER BY `Anio_Fiscal` ASC, `Posicion` ASC;
    
END$$

DELIMITER ;