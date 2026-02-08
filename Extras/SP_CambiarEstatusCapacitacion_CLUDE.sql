/* ====================================================================================================
   ██████╗ ██╗      █████╗ ████████╗██╗███╗   ██╗██╗   ██╗███╗   ███╗
   ██╔══██╗██║     ██╔══██╗╚══██╔══╝██║████╗  ██║██║   ██║████╗ ████║
   ██████╔╝██║     ███████║   ██║   ██║██╔██╗ ██║██║   ██║██╔████╔██║
   ██╔═══╝ ██║     ██╔══██║   ██║   ██║██║╚██╗██║██║   ██║██║╚██╔╝██║
   ██║     ███████╗██║  ██║   ██║   ██║██║ ╚████║╚██████╔╝██║ ╚═╝ ██║
   ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝     ╚═╝
   ███████╗████████╗ █████╗ ███╗   ██╗██████╗  █████╗ ██████╗ ██████╗ 
   ██╔════╝╚══██╔══╝██╔══██╗████╗  ██║██╔══██╗██╔══██╗██╔══██╗██╔══██╗
   ███████╗   ██║   ███████║██╔██╗ ██║██║  ██║███████║██████╔╝██║  ██║
   ╚════██║   ██║   ██╔══██║██║╚██╗██║██║  ██║██╔══██║██╔══██╗██║  ██║
   ███████║   ██║   ██║  ██║██║ ╚████║██████╔╝██║  ██║██║  ██║██████╔╝
   ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ 
   ==================================================================================================== */

/* ====================================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusCapacitacion
   ====================================================================================================
   
   ╔═══════════════════════════════════════════════════════════════════════════════════════════════════╗
   ║  I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)                                            ║
   ╠═══════════════════════════════════════════════════════════════════════════════════════════════════╣
   ║  Nombre Oficial       : SP_CambiarEstatusCapacitacion                                            ║
   ║  Alias Operativo      : "El Interruptor Maestro" / "The Toggle Switch"                           ║
   ║  Versión              : 2.0.0                                                                    ║
   ║  Fecha de Creación    : 2024-XX-XX                                                               ║
   ║  Última Modificación  : 2025-01-XX                                                               ║
   ║  Autor Original       : Equipo de Desarrollo PICADE                                              ║
   ║  Clasificación        : Transacción de Gobernanza de Ciclo de Vida                               ║
   ║                         (Lifecycle Governance Transaction)                                        ║
   ║  Patrón de Diseño     : "Explicit Toggle Switch with State Validation & Audit Injection"         ║
   ║  Criticidad           : ALTA (Afecta la visibilidad global del expediente en todo el sistema)    ║
   ║  Nivel de Aislamiento : SERIALIZABLE (Implícito por el manejo de transacciones atómicas)         ║
   ║  Complejidad Ciclomática: Media (4 caminos de ejecución principales)                             ║
   ╚═══════════════════════════════════════════════════════════════════════════════════════════════════╝

   ╔═══════════════════════════════════════════════════════════════════════════════════════════════════╗
   ║  II. PROPÓSITO FORENSE Y DE NEGOCIO (BUSINESS VALUE PROPOSITION)                                 ║
   ╠═══════════════════════════════════════════════════════════════════════════════════════════════════╣
   ║                                                                                                   ║
   ║  Este procedimiento actúa como el "Interruptor Maestro de Visibilidad" del expediente.           ║
   ║  Su función NO es eliminar datos (DELETE físico está prohibido en el sistema), sino              ║
   ║  controlar la disponibilidad lógica del curso mediante el patrón Soft Delete/Restore.            ║
   ║                                                                                                   ║
   ║  [ANALOGÍA OPERATIVA]:                                                                           ║
   ║  Imagina un archivo físico en un archivero. Este SP es el encargado de:                          ║
   ║    - ARCHIVAR: Mover el expediente del archivero "ACTIVO" al archivero "HISTÓRICO".              ║
   ║    - RESTAURAR: Sacar el expediente del archivero "HISTÓRICO" y regresarlo al "ACTIVO".          ║
   ║  En ningún caso se destruye el expediente; solo se cambia su ubicación lógica.                   ║
   ║                                                                                                   ║
   ║  [DIFERENCIA CON VERSIÓN 1.0]:                                                                   ║
   ║  La versión anterior funcionaba como un "toggle automático" que infería la acción                ║
   ║  basándose en el estado actual. La versión 2.0 requiere que el usuario EXPLÍCITAMENTE            ║
   ║  indique si desea Archivar (0) o Restaurar (1), eliminando ambigüedad y errores de UX.           ║
   ║                                                                                                   ║
   ╚═══════════════════════════════════════════════════════════════════════════════════════════════════╝

   ╔═══════════════════════════════════════════════════════════════════════════════════════════════════╗
   ║  III. REGLAS DE ORO DEL ARCHIVADO - GOVERNANCE RULES                                             ║
   ╠═══════════════════════════════════════════════════════════════════════════════════════════════════╣
   ║                                                                                                   ║
   ║  A. PRINCIPIO DE FINALIZACIÓN (COMPLETION PRINCIPLE)                                             ║
   ║  ─────────────────────────────────────────────────────────────────────────────────────────────── ║
   ║     [REGLA]: No se permite archivar un curso que está "Vivo" (operativamente activo).            ║
   ║                                                                                                   ║
   ║     [MECANISMO]: El sistema verifica la bandera `Es_Final` del catálogo de estatus.              ║
   ║                  Solo los estatus con Es_Final = 1 son archivables.                              ║
   ║                                                                                                   ║
   ║     [ESTATUS ARCHIVABLES (Es_Final = 1)]:                                                        ║
   ║       ┌─────────────────┬───────────┬─────────────────────────────────────────────────┐          ║
   ║       │ Estatus         │ Es_Final  │ Justificación                                   │          ║
   ║       ├─────────────────┼───────────┼─────────────────────────────────────────────────┤          ║
   ║       │ FINALIZADO      │     1     │ Ciclo de vida completado exitosamente           │          ║
   ║       │ CANCELADO       │     1     │ Curso abortado antes de ejecutarse              │          ║
   ║       │ ARCHIVADO       │     1     │ Ya está archivado (idempotencia)                │          ║
   ║       └─────────────────┴───────────┴─────────────────────────────────────────────────┘          ║
   ║                                                                                                   ║
   ║     [ESTATUS NO ARCHIVABLES (Es_Final = 0)]:                                                     ║
   ║       ┌─────────────────┬───────────┬─────────────────────────────────────────────────┐          ║
   ║       │ Estatus         │ Es_Final  │ Razón de Bloqueo                                │          ║
   ║       ├─────────────────┼───────────┼─────────────────────────────────────────────────┤          ║
   ║       │ PROGRAMADO      │     0     │ Curso aún no ha sido autorizado                 │          ║
   ║       │ POR INICIAR     │     0     │ Curso autorizado, esperando fecha de inicio     │          ║
   ║       │ REPROGRAMADO    │     0     │ Curso con cambios pendientes de confirmar       │          ║
   ║       │ EN CURSO        │     0     │ Curso en ejecución activa                       │          ║
   ║       │ EN EVALUACIÓN   │     0     │ Curso terminado, calificaciones pendientes      │          ║
   ║       │ ACREDITADO      │     0     │ Curso aprobado, pendiente de cierre formal      │          ║
   ║       │ NO ACREDITADO   │     0     │ Curso reprobado, pendiente de cierre formal     │          ║
   ║       └─────────────────┴───────────┴─────────────────────────────────────────────────┘          ║
   ║                                                                                                   ║
   ║     [JUSTIFICACIÓN DE NEGOCIO]:                                                                  ║
   ║     Archivar un curso "vivo" causaría su desaparición del Dashboard Operativo,                   ║
   ║     generando confusión en el Coordinador y potencialmente perdiendo el seguimiento              ║
   ║     de un curso que aún requiere atención administrativa.                                        ║
   ║                                                                                                   ║
   ║  B. PRINCIPIO DE CASCADA (CASCADE PRINCIPLE)                                                     ║
   ║  ─────────────────────────────────────────────────────────────────────────────────────────────── ║
   ║     [REGLA]: La acción de Archivar/Restaurar es atómica y jerárquica.                            ║
   ║                                                                                                   ║
   ║     [MECANISMO]: Al modificar el estado del Padre (`Capacitaciones`), se debe                    ║
   ║                  modificar SIMULTÁNEAMENTE el estado del Hijo vigente (`DatosCapacitaciones`).   ║
   ║                                                                                                   ║
   ║     [DIAGRAMA DE CASCADA]:                                                                       ║
   ║                                                                                                   ║
   ║       ARCHIVADO (Activo = 0):                   RESTAURADO (Activo = 1):                         ║
   ║       ┌─────────────────────┐                   ┌─────────────────────┐                          ║
   ║       │   Capacitaciones    │                   │   Capacitaciones    │                          ║
   ║       │   (PADRE)           │                   │   (PADRE)           │                          ║
   ║       │   Activo = 0  ──────┼───┐               │   Activo = 1  ──────┼───┐                      ║
   ║       └─────────────────────┘   │               └─────────────────────┘   │                      ║
   ║                                 │                                         │                      ║
   ║                                 ▼                                         ▼                      ║
   ║       ┌─────────────────────┐                   ┌─────────────────────┐                          ║
   ║       │ DatosCapacitaciones │                   │ DatosCapacitaciones │                          ║
   ║       │ (HIJO VIGENTE)      │                   │ (HIJO VIGENTE)      │                          ║
   ║       │ Activo = 0          │                   │ Activo = 1          │                          ║
   ║       └─────────────────────┘                   └─────────────────────┘                          ║
   ║                                                                                                   ║
   ║     [RAZÓN TÉCNICA]:                                                                             ║
   ║     Las vistas del sistema (`Vista_Capacitaciones`) utilizan INNER JOIN entre Padre e Hijo.      ║
   ║     Si solo se apaga el Padre pero el Hijo sigue activo (o viceversa), el registro               ║
   ║     aparecería en un estado inconsistente o "fantasma" en ciertas consultas.                     ║
   ║                                                                                                   ║
   ║  C. PRINCIPIO DE TRAZABILIDAD AUTOMÁTICA (AUDIT INJECTION STRATEGY)                              ║
   ║  ─────────────────────────────────────────────────────────────────────────────────────────────── ║
   ║     [REGLA]: Cada acción de archivado debe dejar una huella indeleble en el registro.            ║
   ║                                                                                                   ║
   ║     [MECANISMO]: Al archivar, el sistema inyecta automáticamente una "Nota de Sistema"           ║
   ║                  en el campo `Observaciones` del detalle operativo (`DatosCapacitaciones`).      ║
   ║                                                                                                   ║
   ║     [FORMATO DE LA NOTA INYECTADA]:                                                              ║
   ║     ┌──────────────────────────────────────────────────────────────────────────────────────────┐ ║
   ║     │ [SISTEMA]: La capacitación con folio CAP-2026-001 de la Gerencia GER-FINANZAS,          │ ║
   ║     │ fue archivada el 2026-01-15 14:30 porque alcanzó el fin de su ciclo de vida.            │ ║
   ║     └──────────────────────────────────────────────────────────────────────────────────────────┘ ║
   ║                                                                                                   ║
   ║     [OBJETIVO FORENSE]:                                                                          ║
   ║     Que cualquier auditor futuro (interno o externo) pueda determinar:                           ║
   ║       1. QUÉ se archivó (Folio).                                                                 ║
   ║       2. DE QUIÉN era (Gerencia responsable).                                                    ║
   ║       3. CUÁNDO se archivó (Timestamp exacto).                                                   ║
   ║       4. POR QUÉ se archivó (Fin del ciclo de vida).                                             ║
   ║                                                                                                   ║
   ║  D. PRINCIPIO DE IDEMPOTENCIA (IDEMPOTENCY GUARANTEE)                                            ║
   ║  ─────────────────────────────────────────────────────────────────────────────────────────────── ║
   ║     [REGLA]: Ejecutar la misma operación múltiples veces produce el mismo resultado.             ║
   ║                                                                                                   ║
   ║     [MECANISMO]: Antes de ejecutar cualquier UPDATE, el SP verifica si el expediente             ║
   ║                  YA está en el estado solicitado. Si es así, retorna un mensaje informativo      ║
   ║                  sin realizar cambios ni generar errores.                                        ║
   ║                                                                                                   ║
   ║     [EJEMPLO]:                                                                                   ║
   ║       - Usuario llama: SP_CambiarEstatusCapacitacion(123, 1, 0) -- Archivar                      ║
   ║       - El expediente 123 ya está archivado (Activo = 0).                                        ║
   ║       - Resultado: "La Capacitación ya se encuentra en el estado ARCHIVADO."                     ║
   ║       - Acción: SIN_CAMBIOS (no se escribe nada en la BD).                                       ║
   ║                                                                                                   ║
   ╚═══════════════════════════════════════════════════════════════════════════════════════════════════╝

   ╔═══════════════════════════════════════════════════════════════════════════════════════════════════╗
   ║  IV. ARQUITECTURA DE DEFENSA EN PROFUNDIDAD (DEFENSE IN DEPTH)                                   ║
   ╠═══════════════════════════════════════════════════════════════════════════════════════════════════╣
   ║                                                                                                   ║
   ║  El procedimiento implementa 5 capas de seguridad concéntricas:                                  ║
   ║                                                                                                   ║
   ║  ┌─────────────────────────────────────────────────────────────────────────────────────────────┐ ║
   ║  │                                                                                             │ ║
   ║  │   ┌───────────────────────────────────────────────────────────────────────────────────┐    │ ║
   ║  │   │                                                                                   │    │ ║
   ║  │   │   ┌───────────────────────────────────────────────────────────────────────┐      │    │ ║
   ║  │   │   │                                                                       │      │    │ ║
   ║  │   │   │   ┌───────────────────────────────────────────────────────────┐      │      │    │ ║
   ║  │   │   │   │                                                           │      │      │    │ ║
   ║  │   │   │   │   ┌───────────────────────────────────────────────┐      │      │      │    │ ║
   ║  │   │   │   │   │          CAPA 5: ATOMICIDAD (ACID)            │      │      │      │    │ ║
   ║  │   │   │   │   │          Transaction + Rollback               │      │      │      │    │ ║
   ║  │   │   │   │   └───────────────────────────────────────────────┘      │      │      │    │ ║
   ║  │   │   │   │              CAPA 4: VALIDACIÓN DE NEGOCIO               │      │      │    │ ║
   ║  │   │   │   │              Es_Final = 1 para archivar                  │      │      │    │ ║
   ║  │   │   │   └───────────────────────────────────────────────────────────┘      │      │    │ ║
   ║  │   │   │                  CAPA 3: IDEMPOTENCIA                                 │      │    │ ║
   ║  │   │   │                  Verificar estado actual                              │      │    │ ║
   ║  │   │   └───────────────────────────────────────────────────────────────────────┘      │    │ ║
   ║  │   │                      CAPA 2: EXISTENCIA                                          │    │ ║
   ║  │   │                      Verificar que el expediente existe                          │    │ ║
   ║  │   └───────────────────────────────────────────────────────────────────────────────────┘    │ ║
   ║  │                          CAPA 1: VALIDACIÓN DE INPUTS                                      │ ║
   ║  │                          Sanitización de parámetros                                        │ ║
   ║  └─────────────────────────────────────────────────────────────────────────────────────────────┘ ║
   ║                                                                                                   ║
   ║  [DETALLE DE CADA CAPA]:                                                                         ║
   ║                                                                                                   ║
   ║  CAPA 1 - VALIDACIÓN DE INPUTS (INPUT SANITIZATION)                                              ║
   ║  ────────────────────────────────────────────────────                                            ║
   ║    • Objetivo: Rechazar datos basura antes de procesar.                                          ║
   ║    • Validaciones:                                                                               ║
   ║      - _Id_Capacitacion: NOT NULL, > 0                                                           ║
   ║      - _Id_Usuario_Ejecutor: NOT NULL, > 0                                                       ║
   ║      - _Nuevo_Estatus: NOT NULL, IN (0, 1)                                                       ║
   ║    • Error: SQLSTATE 45000 con código [400] Bad Request.                                         ║
   ║                                                                                                   ║
   ║  CAPA 2 - VERIFICACIÓN DE EXISTENCIA (EXISTENCE CHECK)                                           ║
   ║  ───────────────────────────────────────────────────────                                         ║
   ║    • Objetivo: Confirmar que el expediente existe en la BD.                                      ║
   ║    • Mecanismo: SELECT sobre `Capacitaciones` con el ID proporcionado.                           ║
   ║    • Error: SQLSTATE 45000 con código [404] Not Found.                                           ║
   ║                                                                                                   ║
   ║  CAPA 3 - IDEMPOTENCIA (IDEMPOTENCY CHECK)                                                       ║
   ║  ──────────────────────────────────────────                                                      ║
   ║    • Objetivo: Evitar operaciones redundantes.                                                   ║
   ║    • Mecanismo: Comparar estado actual vs estado solicitado.                                     ║
   ║    • Resultado si iguales: Retorno informativo sin cambios.                                      ║
   ║                                                                                                   ║
   ║  CAPA 4 - VALIDACIÓN DE REGLAS DE NEGOCIO (BUSINESS RULES)                                       ║
   ║  ──────────────────────────────────────────────────────────                                      ║
   ║    • Objetivo: Aplicar restricciones del dominio de negocio.                                     ║
   ║    • Regla: Solo estatus con Es_Final = 1 pueden archivarse.                                     ║
   ║    • Error: SQLSTATE 45000 con código [409] Conflict.                                            ║
   ║                                                                                                   ║
   ║  CAPA 5 - ATOMICIDAD TRANSACCIONAL (ACID COMPLIANCE)                                             ║
   ║  ─────────────────────────────────────────────────────                                           ║
   ║    • Objetivo: Garantizar consistencia total (Todo o Nada).                                      ║
   ║    • Mecanismo: START TRANSACTION + COMMIT/ROLLBACK.                                             ║
   ║    • Handler: EXIT HANDLER FOR SQLEXCEPTION ejecuta ROLLBACK automático.                         ║
   ║                                                                                                   ║
   ╚═══════════════════════════════════════════════════════════════════════════════════════════════════╝

   ╔═══════════════════════════════════════════════════════════════════════════════════════════════════╗
   ║  V. ESPECIFICACIÓN DE INTERFAZ (CONTRACT SPECIFICATION)                                          ║
   ╠═══════════════════════════════════════════════════════════════════════════════════════════════════╣
   ║                                                                                                   ║
   ║  [ENTRADA - INPUT PARAMETERS]                                                                    ║
   ║  ─────────────────────────────                                                                   ║
   ║  ┌────────────────────────┬─────────┬────────────┬───────────────────────────────────────────┐   ║
   ║  │ Parámetro              │ Tipo    │ Requerido  │ Descripción                               │   ║
   ║  ├────────────────────────┼─────────┼────────────┼───────────────────────────────────────────┤   ║
   ║  │ _Id_Capacitacion       │ INT     │ SÍ         │ ID del Expediente Maestro (Padre).        │   ║
   ║  │                        │         │            │ Apunta a `Capacitaciones.Id_Capacitacion`.│   ║
   ║  ├────────────────────────┼─────────┼────────────┼───────────────────────────────────────────┤   ║
   ║  │ _Id_Usuario_Ejecutor   │ INT     │ SÍ         │ ID del usuario que ejecuta la acción.     │   ║
   ║  │                        │         │            │ Requerido para la auditoría (Updated_by). │   ║
   ║  ├────────────────────────┼─────────┼────────────┼───────────────────────────────────────────┤   ║
   ║  │ _Nuevo_Estatus         │ TINYINT │ SÍ         │ Acción explícita a realizar:              │   ║
   ║  │                        │         │            │   • 0 = ARCHIVAR (Soft Delete)            │   ║
   ║  │                        │         │            │   • 1 = RESTAURAR (Undelete)              │   ║
   ║  └────────────────────────┴─────────┴────────────┴───────────────────────────────────────────┘   ║
   ║                                                                                                   ║
   ║  [SALIDA - OUTPUT RESULTSET]                                                                     ║
   ║  ────────────────────────────                                                                    ║
   ║  Retorna un Resultset de fila única (Single Row) con la confirmación de la operación:            ║
   ║                                                                                                   ║
   ║  ┌────────────────┬─────────────┬────────────────────────────────────────────────────────────┐   ║
   ║  │ Columna        │ Tipo        │ Descripción                                                │   ║
   ║  ├────────────────┼─────────────┼────────────────────────────────────────────────────────────┤   ║
   ║  │ Nuevo_Estado   │ VARCHAR(20) │ Estado resultante: 'ARCHIVADO' o 'RESTAURADO'.             │   ║
   ║  ├────────────────┼─────────────┼────────────────────────────────────────────────────────────┤   ║
   ║  │ Mensaje        │ VARCHAR(200)│ Descripción legible del resultado de la operación.        │   ║
   ║  ├────────────────┼─────────────┼────────────────────────────────────────────────────────────┤   ║
   ║  │ Accion         │ VARCHAR(20) │ Código de acción para el Frontend:                        │   ║
   ║  │                │             │   • 'ESTATUS_CAMBIADO' = Operación exitosa.               │   ║
   ║  │                │             │   • 'SIN_CAMBIOS' = Ya estaba en ese estado.              │   ║
   ║  └────────────────┴─────────────┴────────────────────────────────────────────────────────────┘   ║
   ║                                                                                                   ║
   ║  [CÓDIGOS DE ERROR - ERROR CODES]                                                                ║
   ║  ─────────────────────────────────                                                               ║
   ║  El procedimiento utiliza códigos de error estándar HTTP-like para facilitar la integración:     ║
   ║                                                                                                   ║
   ║  ┌─────────┬────────────────────────────────────────────────────────────────────────────────┐    ║
   ║  │ Código  │ Descripción                                                                    │    ║
   ║  ├─────────┼────────────────────────────────────────────────────────────────────────────────┤    ║
   ║  │ [400]   │ Bad Request - Parámetros de entrada inválidos (NULL, negativos, fuera de      │    ║
   ║  │         │ dominio). El cliente debe corregir los datos antes de reintentar.             │    ║
   ║  ├─────────┼────────────────────────────────────────────────────────────────────────────────┤    ║
   ║  │ [404]   │ Not Found - La capacitación solicitada no existe en la base de datos.         │    ║
   ║  │         │ Posiblemente fue eliminada físicamente o el ID es incorrecto.                 │    ║
   ║  ├─────────┼────────────────────────────────────────────────────────────────────────────────┤    ║
   ║  │ [409]   │ Conflict - Violación de reglas de negocio. El estatus actual no permite       │    ║
   ║  │         │ el archivado porque Es_Final = 0 (el curso sigue "vivo").                     │    ║
   ║  └─────────┴────────────────────────────────────────────────────────────────────────────────┘    ║
   ║                                                                                                   ║
   ╚═══════════════════════════════════════════════════════════════════════════════════════════════════╝

   ╔═══════════════════════════════════════════════════════════════════════════════════════════════════╗
   ║  VI. DIAGRAMA DE FLUJO DE EJECUCIÓN (EXECUTION FLOW)                                             ║
   ╠═══════════════════════════════════════════════════════════════════════════════════════════════════╣
   ║                                                                                                   ║
   ║                              ┌─────────────────────┐                                              ║
   ║                              │    INICIO (CALL)    │                                              ║
   ║                              └──────────┬──────────┘                                              ║
   ║                                         │                                                         ║
   ║                                         ▼                                                         ║
   ║                              ┌─────────────────────┐                                              ║
   ║                              │ CAPA 1: Validar     │                                              ║
   ║                              │ Inputs (NULL, <0)   │                                              ║
   ║                              └──────────┬──────────┘                                              ║
   ║                                         │                                                         ║
   ║                           ┌─────────────┴─────────────┐                                           ║
   ║                           │ ¿Inputs válidos?          │                                           ║
   ║                           └─────────────┬─────────────┘                                           ║
   ║                          NO             │            SÍ                                           ║
   ║                    ┌─────────────┐      │      ┌─────────────┐                                    ║
   ║                    │ ERROR [400] │      │      │             │                                    ║
   ║                    │ Bad Request │      │      ▼             │                                    ║
   ║                    └─────────────┘      │ ┌─────────────────────┐                                 ║
   ║                                         │ │ CAPA 2: Verificar   │                                 ║
   ║                                         │ │ Existencia (SELECT) │                                 ║
   ║                                         │ └──────────┬──────────┘                                 ║
   ║                                         │            │                                            ║
   ║                                         │ ┌──────────┴──────────┐                                 ║
   ║                                         │ │ ¿Existe el registro?│                                 ║
   ║                                         │ └──────────┬──────────┘                                 ║
   ║                                         │  NO        │        SÍ                                  ║
   ║                                  ┌─────────────┐     │     ┌─────────────┐                        ║
   ║                                  │ ERROR [404] │     │     │             │                        ║
   ║                                  │ Not Found   │     │     ▼             │                        ║
   ║                                  └─────────────┘     │ ┌─────────────────────┐                    ║
   ║                                                      │ │ CAPA 3: Verificar   │                    ║
   ║                                                      │ │ Idempotencia        │                    ║
   ║                                                      │ └──────────┬──────────┘                    ║
   ║                                                      │            │                               ║
   ║                                                      │ ┌──────────┴──────────┐                    ║
   ║                                                      │ │ ¿Ya está en ese     │                    ║
   ║                                                      │ │ estado?             │                    ║
   ║                                                      │ └──────────┬──────────┘                    ║
   ║                                                      │  SÍ        │        NO                     ║
   ║                                               ┌─────────────┐     │     ┌─────────────┐           ║
   ║                                               │ SIN_CAMBIOS │     │     │             │           ║
   ║                                               │ (Informar)  │     │     ▼             │           ║
   ║                                               └─────────────┘     │ ┌─────────────────────┐       ║
   ║                                                                   │ │ ¿Acción solicitada? │       ║
   ║                                                                   │ └──────────┬──────────┘       ║
   ║                                                                   │            │                  ║
   ║                                          ┌────────────────────────┴────────────┴──────────┐       ║
   ║                                          │                                                │       ║
   ║                                 _Nuevo_Estatus = 0                           _Nuevo_Estatus = 1   ║
   ║                                    (ARCHIVAR)                                   (RESTAURAR)       ║
   ║                                          │                                                │       ║
   ║                                          ▼                                                ▼       ║
   ║                              ┌─────────────────────┐                      ┌─────────────────────┐ ║
   ║                              │ CAPA 4: Validar     │                      │ Ejecutar UPDATE     │ ║
   ║                              │ Es_Final = 1        │                      │ Activo = 1          │ ║
   ║                              └──────────┬──────────┘                      │ (Padre + Hijo)      │ ║
   ║                                         │                                 └──────────┬──────────┘ ║
   ║                           ┌─────────────┴─────────────┐                              │            ║
   ║                           │ ¿Es_Final = 1?            │                              │            ║
   ║                           └─────────────┬─────────────┘                              │            ║
   ║                          NO             │            SÍ                              │            ║
   ║                    ┌─────────────┐      │      ┌─────────────────────┐               │            ║
   ║                    │ ERROR [409] │      │      │ CAPA 5: Ejecutar    │               │            ║
   ║                    │ Conflict    │      │      │ UPDATE Activo = 0   │               │            ║
   ║                    └─────────────┘      │      │ (Padre + Hijo)      │               │            ║
   ║                                         │      │ + Inyectar Nota     │               │            ║
   ║                                         │      └──────────┬──────────┘               │            ║
   ║                                         │                 │                          │            ║
   ║                                         │                 ▼                          ▼            ║
   ║                                         │      ┌─────────────────────┐    ┌─────────────────────┐ ║
   ║                                         │      │ COMMIT + Retornar   │    │ COMMIT + Retornar   │ ║
   ║                                         │      │ "ARCHIVADO"         │    │ "RESTAURADO"        │ ║
   ║                                         │      └─────────────────────┘    └─────────────────────┘ ║
   ║                                         │                                                         ║
   ╚═══════════════════════════════════════════════════════════════════════════════════════════════════╝

   ╔═══════════════════════════════════════════════════════════════════════════════════════════════════╗
   ║  VII. CASOS DE USO Y EJEMPLOS (USE CASES & EXAMPLES)                                             ║
   ╠═══════════════════════════════════════════════════════════════════════════════════════════════════╣
   ║                                                                                                   ║
   ║  [CASO 1: ARCHIVADO EXITOSO]                                                                     ║
   ║  ────────────────────────────                                                                    ║
   ║    Contexto: Curso CAP-2026-001 está en estatus FINALIZADO (Es_Final = 1).                       ║
   ║    Llamada:  CALL SP_CambiarEstatusCapacitacion(123, 1, 0);                                      ║
   ║    Resultado:                                                                                    ║
   ║      ┌────────────────┬──────────────────────────────────────────┬──────────────────┐            ║
   ║      │ Nuevo_Estado   │ Mensaje                                  │ Accion           │            ║
   ║      ├────────────────┼──────────────────────────────────────────┼──────────────────┤            ║
   ║      │ ARCHIVADO      │ Expediente archivado y nota de auditoría │ ESTATUS_CAMBIADO │            ║
   ║      │                │ registrada.                              │                  │            ║
   ║      └────────────────┴──────────────────────────────────────────┴──────────────────┘            ║
   ║                                                                                                   ║
   ║  [CASO 2: ARCHIVADO BLOQUEADO]                                                                   ║
   ║  ─────────────────────────────                                                                   ║
   ║    Contexto: Curso CAP-2026-002 está en estatus EN CURSO (Es_Final = 0).                         ║
   ║    Llamada:  CALL SP_CambiarEstatusCapacitacion(124, 1, 0);                                      ║
   ║    Resultado: ERROR                                                                              ║
   ║      ┌──────────────────────────────────────────────────────────────────────────────────────────┐║
   ║      │ ACCIÓN DENEGADA [409]: No se puede archivar un curso activo.                            │║
   ║      │ El estatus actual es "EN CURSO", el cual se considera OPERATIVO (No Final).             │║
   ║      │ Debe finalizar o cancelar la capacitación antes de archivarla.                          │║
   ║      └──────────────────────────────────────────────────────────────────────────────────────────┘║
   ║                                                                                                   ║
   ║  [CASO 3: RESTAURACIÓN EXITOSA]                                                                  ║
   ║  ───────────────────────────────                                                                 ║
   ║    Contexto: Curso CAP-2026-001 está archivado (Activo = 0).                                     ║
   ║    Llamada:  CALL SP_CambiarEstatusCapacitacion(123, 1, 1);                                      ║
   ║    Resultado:                                                                                    ║
   ║      ┌────────────────┬──────────────────────────────────────────┬──────────────────┐            ║
   ║      │ Nuevo_Estado   │ Mensaje                                  │ Accion           │            ║
   ║      ├────────────────┼──────────────────────────────────────────┼──────────────────┤            ║
   ║      │ RESTAURADO     │ Expediente restaurado exitosamente.      │ ESTATUS_CAMBIADO │            ║
   ║      └────────────────┴──────────────────────────────────────────┴──────────────────┘            ║
   ║                                                                                                   ║
   ║  [CASO 4: OPERACIÓN IDEMPOTENTE]                                                                 ║
   ║  ────────────────────────────────                                                                ║
   ║    Contexto: Curso CAP-2026-001 ya está archivado (Activo = 0).                                  ║
   ║    Llamada:  CALL SP_CambiarEstatusCapacitacion(123, 1, 0);  -- Intenta archivar de nuevo        ║
   ║    Resultado:                                                                                    ║
   ║      ┌─────────────────────────────────────────────────────────────────┬──────────────┐          ║
   ║      │ Mensaje                                                         │ Accion       │          ║
   ║      ├─────────────────────────────────────────────────────────────────┼──────────────┤          ║
   ║      │ AVISO: La Capacitación "CAP-2026-001" ya se encuentra en el     │ SIN_CAMBIOS  │          ║
   ║      │ estado solicitado (ARCHIVADO).                                  │              │          ║
   ║      └─────────────────────────────────────────────────────────────────┴──────────────┘          ║
   ║                                                                                                   ║
   ╚═══════════════════════════════════════════════════════════════════════════════════════════════════╝

   ╔═══════════════════════════════════════════════════════════════════════════════════════════════════╗
   ║  VIII. HISTORIAL DE CAMBIOS (CHANGELOG)                                                          ║
   ╠═══════════════════════════════════════════════════════════════════════════════════════════════════╣
   ║                                                                                                   ║
   ║  [v1.0.0] - Fecha Original                                                                       ║
   ║  ─────────────────────────────                                                                   ║
   ║    • Versión inicial con comportamiento "toggle" automático.                                     ║
   ║    • El SP infería la acción basándose en el estado actual.                                      ║
   ║                                                                                                   ║
   ║  [v2.0.0] - 2025-01-XX                                                                           ║
   ║  ─────────────────────────────                                                                   ║
   ║    • BREAKING CHANGE: Nuevo parámetro obligatorio `_Nuevo_Estatus`.                              ║
   ║    • Ahora el usuario debe indicar EXPLÍCITAMENTE si desea archivar (0) o restaurar (1).         ║
   ║    • Agregada validación de dominio estricta para _Nuevo_Estatus (solo 0 o 1).                   ║
   ║    • Mejorada la documentación con diagramas ASCII y ejemplos.                                   ║
   ║                                                                                                   ║
   ╚═══════════════════════════════════════════════════════════════════════════════════════════════════╝

   ==================================================================================================== */

DELIMITER $$

/* ---------------------------------------------------------------------------------------------------
   LIMPIEZA PREVENTIVA (IDEMPOTENT DROP)
   ---------------------------------------------------------------------------------------------------
   [OBJETIVO]: Eliminar cualquier versión anterior del SP antes de recrearlo.
   [JUSTIFICACIÓN]: MySQL no soporta CREATE OR REPLACE PROCEDURE, por lo que debemos usar DROP + CREATE.
   [SEGURIDAD]: El IF EXISTS previene errores si el SP no existe previamente.
   --------------------------------------------------------------------------------------------------- */
DROP PROCEDURE IF EXISTS `SP_CambiarEstatusCapacitacion`$$

CREATE PROCEDURE `SP_CambiarEstatusCapacitacion`(
    /* ===============================================================================================
       SECCIÓN DE PARÁMETROS DE ENTRADA (INPUT PARAMETERS SECTION)
       ===============================================================================================
       
       Esta sección define el "Contrato de Interfaz" del procedimiento.
       Cada parámetro está documentado con su tipo, obligatoriedad y propósito.
       
       [PRINCIPIO DE DISEÑO]: Explicit Input over Implicit Inference
       En lugar de inferir la acción del estado actual (como en v1.0), requerimos que
       el llamador indique EXPLÍCITAMENTE qué acción desea realizar.
       =============================================================================================== */
    
    /* -----------------------------------------------------------------------------------------------
       PARÁMETRO 1: _Id_Capacitacion
       -----------------------------------------------------------------------------------------------
       [TIPO DE DATO]    : INT (Entero de 32 bits con signo)
       [OBLIGATORIEDAD]  : REQUERIDO (NOT NULL, > 0)
       [DESCRIPCIÓN]     : Identificador único del Expediente Maestro (tabla `Capacitaciones`).
       [ORIGEN DEL VALOR]: El Frontend obtiene este ID cuando el usuario selecciona una fila
                           en el Grid del Dashboard o en el resultado de una búsqueda.
       [RELACIÓN FK]     : Apunta a `Capacitaciones.Id_Capacitacion` (PRIMARY KEY).
       [VALIDACIÓN]      : 
         - No puede ser NULL (se rechaza con error [400]).
         - No puede ser <= 0 (los IDs autogenerados siempre son positivos).
       [EJEMPLO]         : 123 (ID interno), NO confundir con el Folio (ej: 'CAP-2026-001').
       ----------------------------------------------------------------------------------------------- */
    IN _Id_Capacitacion     INT,
    
    /* -----------------------------------------------------------------------------------------------
       PARÁMETRO 2: _Id_Usuario_Ejecutor
       -----------------------------------------------------------------------------------------------
       [TIPO DE DATO]    : INT (Entero de 32 bits con signo)
       [OBLIGATORIEDAD]  : REQUERIDO (NOT NULL, > 0)
       [DESCRIPCIÓN]     : Identificador del usuario que ejecuta la operación de archivado/restauración.
       [PROPÓSITO FORENSE]: Este valor se utiliza para poblar los campos de auditoría:
         - `Capacitaciones.Fk_Id_Usuario_Cap_Updated_by`
         - `DatosCapacitaciones.Fk_Id_Usuario_DatosCap_Updated_by`
       [ORIGEN DEL VALOR]: El Backend (Laravel) extrae este ID de la sesión autenticada del usuario.
       [RELACIÓN FK]     : Apunta a `Usuarios.Id_Usuario` (PRIMARY KEY).
       [VALIDACIÓN]      : 
         - No puede ser NULL (se rechaza con error [400]).
         - No puede ser <= 0 (los IDs autogenerados siempre son positivos).
       [NOTA DE SEGURIDAD]: El Backend DEBE validar que el usuario tenga permisos de Coordinador o Admin
                            antes de llamar a este SP. El SP no valida roles internamente.
       ----------------------------------------------------------------------------------------------- */
    IN _Id_Usuario_Ejecutor INT,
    
    /* -----------------------------------------------------------------------------------------------
       PARÁMETRO 3: _Nuevo_Estatus
       -----------------------------------------------------------------------------------------------
       [TIPO DE DATO]    : TINYINT (Entero de 8 bits: 0-255, usamos solo 0 y 1)
       [OBLIGATORIEDAD]  : REQUERIDO (NOT NULL, IN (0, 1))
       [DESCRIPCIÓN]     : Indicador EXPLÍCITO de la acción a realizar.
       [DOMINIO DE VALORES]:
         ┌───────┬────────────────┬──────────────────────────────────────────────────────────────┐
         │ Valor │ Acción         │ Efecto                                                       │
         ├───────┼────────────────┼──────────────────────────────────────────────────────────────┤
         │   0   │ ARCHIVAR       │ Cambia Activo=0 en Padre e Hijo. Inyecta nota de auditoría.  │
         │       │ (Soft Delete)  │ El expediente desaparece del Dashboard Operativo.            │
         ├───────┼────────────────┼──────────────────────────────────────────────────────────────┤
         │   1   │ RESTAURAR      │ Cambia Activo=1 en Padre e Hijo.                             │
         │       │ (Undelete)     │ El expediente reaparece en el Dashboard Operativo.           │
         └───────┴────────────────┴──────────────────────────────────────────────────────────────┘
       [JUSTIFICACIÓN DEL CAMBIO v1.0 → v2.0]:
         La versión 1.0 usaba un "toggle" implícito: si estaba activo, lo archivaba; si estaba
         archivado, lo restauraba. Esto generaba confusión en la UX porque el usuario no sabía
         qué iba a pasar al presionar el botón. La v2.0 requiere intención explícita.
       [VALIDACIÓN]      : 
         - No puede ser NULL (se rechaza con error [400]).
         - Solo acepta 0 o 1 (cualquier otro valor genera error [400]).
       ----------------------------------------------------------------------------------------------- */
    IN _Nuevo_Estatus       TINYINT
)
/* ===================================================================================================
   ETIQUETA DEL PROCEDIMIENTO (PROCEDURE LABEL)
   ===================================================================================================
   [NOMBRE]: THIS_PROC
   [PROPÓSITO]: Permite usar `LEAVE THIS_PROC;` para salir del procedimiento de forma controlada
                sin ejecutar el resto del código. Es más limpio que usar múltiples RETURN o flags.
   [USO]: Se utiliza en el bloque de Idempotencia para salir anticipadamente cuando no hay cambios.
   =================================================================================================== */
THIS_PROC: BEGIN

    /* ===============================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ENTORNO (ENVIRONMENT VARIABLES DECLARATION)
       ===============================================================================================
       
       [PROPÓSITO]:
       Definir todos los contenedores de memoria que el procedimiento utilizará durante su ejecución.
       MySQL requiere que TODAS las variables DECLARE se definan ANTES de cualquier otra instrucción.
       
       [ESTRATEGIA DE NOMENCLATURA]:
       Todas las variables locales usan el prefijo `v_` para distinguirlas de:
         - Parámetros de entrada (prefijo `_`)
         - Columnas de tablas (sin prefijo)
       
       [CATEGORÍAS DE VARIABLES]:
         1. Variables de Estado del Padre (Parent State Variables)
         2. Variables de Estado del Hijo (Child State Variables)
         3. Variables de Reglas de Negocio (Business Rule Variables)
         4. Variables de Auditoría (Audit Variables)
       =============================================================================================== */
    
    /* -----------------------------------------------------------------------------------------------
       CATEGORÍA 1: VARIABLES DE ESTADO DEL PADRE (PARENT STATE VARIABLES)
       ----------------------------------------------------------------------------------------------- */
    
    /* [VARIABLE]: v_Estado_Actual_Padre
       [TIPO]    : TINYINT(1) - Booleano (0 o 1)
       [PROPÓSITO]: Almacenar el valor actual del campo `Capacitaciones.Activo`.
       [USO]     : 
         - Determinar si el expediente está actualmente ACTIVO (1) o ARCHIVADO (0).
         - Comparar con `_Nuevo_Estatus` para verificar idempotencia.
       [FLUJO DE DATOS]: SELECT `Activo` INTO v_Estado_Actual_Padre FROM `Capacitaciones`... */
    DECLARE v_Estado_Actual_Padre TINYINT(1); 
    
    /* -----------------------------------------------------------------------------------------------
       CATEGORÍA 2: VARIABLES DE ESTADO DEL HIJO (CHILD STATE VARIABLES)
       ----------------------------------------------------------------------------------------------- */
    
    /* [VARIABLE]: v_Id_Ultimo_Detalle
       [TIPO]    : INT - Entero de 32 bits
       [PROPÓSITO]: Almacenar el ID de la versión VIGENTE del detalle operativo (`DatosCapacitaciones`).
       [CONTEXTO]: Un expediente padre puede tener múltiples versiones hijas (historial de cambios).
                   Solo la última versión (MAX(Id_DatosCap)) es la "vigente".
       [USO]     : 
         - Saber cuál registro hijo actualizar cuando se archive/restaure.
         - Inyectar la nota de auditoría en el detalle correcto.
       [FLUJO DE DATOS]: SELECT MAX(`Id_DatosCap`) INTO v_Id_Ultimo_Detalle FROM `DatosCapacitaciones`... */
    DECLARE v_Id_Ultimo_Detalle INT;           
    
    /* -----------------------------------------------------------------------------------------------
       CATEGORÍA 3: VARIABLES DE REGLAS DE NEGOCIO (BUSINESS RULE VARIABLES)
       ----------------------------------------------------------------------------------------------- */
    
    /* [VARIABLE]: v_Es_Estatus_Final
       [TIPO]    : TINYINT(1) - Booleano (0 o 1)
       [PROPÓSITO]: Almacenar la bandera `Es_Final` del catálogo de estatus (`Cat_Estatus_Capacitacion`).
       [REGLA DE NEGOCIO]:
         - Es_Final = 1: El estatus es TERMINAL (FINALIZADO, CANCELADO, ARCHIVADO). SE PUEDE ARCHIVAR.
         - Es_Final = 0: El estatus es OPERATIVO (PROGRAMADO, EN CURSO, etc.). NO SE PUEDE ARCHIVAR.
       [USO]     : Validar si el archivado está permitido según las reglas de gobernanza.
       [FLUJO DE DATOS]: SELECT `Es_Final` INTO v_Es_Estatus_Final FROM `Cat_Estatus_Capacitacion`... */
    DECLARE v_Es_Estatus_Final TINYINT(1);
    
    /* [VARIABLE]: v_Nombre_Estatus
       [TIPO]    : VARCHAR(50) - Cadena de texto de hasta 50 caracteres
       [PROPÓSITO]: Almacenar el nombre legible del estatus actual (ej: "EN CURSO", "FINALIZADO").
       [USO]     : Construir mensajes de error descriptivos que ayuden al usuario a entender
                   por qué su solicitud de archivado fue rechazada.
       [EJEMPLO DE USO EN MENSAJE]:
         "El estatus actual es 'EN CURSO', el cual se considera OPERATIVO (No Final)."
       [FLUJO DE DATOS]: SELECT `Nombre` INTO v_Nombre_Estatus FROM `Cat_Estatus_Capacitacion`... */
    DECLARE v_Nombre_Estatus VARCHAR(50);
    
    /* -----------------------------------------------------------------------------------------------
       CATEGORÍA 4: VARIABLES DE AUDITORÍA (AUDIT VARIABLES)
       ----------------------------------------------------------------------------------------------- */
    
    /* [VARIABLE]: v_Folio
       [TIPO]    : VARCHAR(50) - Cadena de texto de hasta 50 caracteres
       [PROPÓSITO]: Almacenar el Folio/Número de Capacitación (ej: "CAP-2026-001").
       [USO]     : 
         - Incluir en el mensaje de idempotencia para que el usuario sepa qué curso se verificó.
         - Incluir en la nota de auditoría inyectada al archivar.
       [CONTEXTO]: El Folio es la "Llave de Negocio" que los usuarios reconocen. El Id interno
                   es solo para uso técnico.
       [FLUJO DE DATOS]: SELECT `Numero_Capacitacion` INTO v_Folio FROM `Capacitaciones`... */
    DECLARE v_Folio VARCHAR(50);
    
    /* [VARIABLE]: v_Clave_Gerencia
       [TIPO]    : VARCHAR(50) - Cadena de texto de hasta 50 caracteres
       [PROPÓSITO]: Almacenar la Clave de la Gerencia responsable del curso (ej: "GER-FINANZAS").
       [USO]     : Incluir en la nota de auditoría para identificar el área organizacional afectada.
       [CONTEXTO FORENSE]: En una auditoría, es crítico saber no solo QUÉ curso se archivó,
                           sino también DE QUIÉN era la responsabilidad de ese curso.
       [FLUJO DE DATOS]: SELECT `Clave` INTO v_Clave_Gerencia FROM `Cat_Gerencias_Activos`... */
    DECLARE v_Clave_Gerencia VARCHAR(50);
    
    /* [VARIABLE]: v_Mensaje_Auditoria
       [TIPO]    : TEXT - Cadena de texto de longitud variable (hasta 65,535 caracteres)
       [PROPÓSITO]: Almacenar el mensaje formateado que se inyectará en el campo `Observaciones`.
       [FORMATO DEL MENSAJE]:
         "[SISTEMA]: La capacitación con folio {FOLIO} de la Gerencia {GERENCIA}, 
          fue archivada el {FECHA} porque alcanzó el fin de su ciclo de vida."
       [USO]     : Concatenar con las observaciones existentes al archivar para dejar evidencia.
       [NOTA]    : Se usa TEXT en lugar de VARCHAR porque el mensaje puede ser largo y además
                   se concatena con observaciones previas que también pueden ser extensas. */
    DECLARE v_Mensaje_Auditoria TEXT;

    /* ===============================================================================================
       BLOQUE 1: HANDLER DE EXCEPCIONES (EXCEPTION HANDLER - FAIL-SAFE MECHANISM)
       ===============================================================================================
       
       [PROPÓSITO]:
       Definir el comportamiento del sistema ante errores inesperados (excepciones SQL).
       Este es el "Airbag" del procedimiento: si algo sale mal, revierte todo y no deja datos corruptos.
       
       [PRINCIPIO ACID]:
       Este handler garantiza la "Atomicidad" de la transacción. Si cualquier parte falla,
       TODO se revierte, dejando la base de datos exactamente como estaba antes del CALL.
       
       [TIPOS DE ERRORES CAPTURADOS]:
         - Errores de disco (ej: tablespace lleno)
         - Errores de conexión (ej: timeout)
         - Violaciones de FK no anticipadas
         - Errores de sintaxis en SQL dinámico
         - Cualquier otro SQLEXCEPTION no manejado específicamente
       
       [COMPORTAMIENTO]:
         1. ROLLBACK: Revierte todos los cambios pendientes de la transacción actual.
         2. RESIGNAL: Re-lanza la excepción original para que el llamador (Backend) la capture.
       
       [NOTA TÉCNICA]:
       Usamos EXIT HANDLER (termina el SP inmediatamente) en lugar de CONTINUE HANDLER
       (seguiría ejecutando) porque ante un error de sistema no tiene sentido continuar.
       =============================================================================================== */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        /* -------------------------------------------------------------------------------------
           PASO 1: ROLLBACK DE EMERGENCIA
           -------------------------------------------------------------------------------------
           [ACCIÓN]  : Deshacer todos los cambios realizados desde el último START TRANSACTION.
           [EFECTO]  : Los UPDATEs a `Capacitaciones` y `DatosCapacitaciones` se revierten.
           [GARANTÍA]: La BD queda en el estado exacto en que estaba antes del CALL.
           ------------------------------------------------------------------------------------- */
        ROLLBACK; 
        
        /* -------------------------------------------------------------------------------------
           PASO 2: PROPAGACIÓN DEL ERROR (RESIGNAL)
           -------------------------------------------------------------------------------------
           [ACCIÓN]  : Re-lanzar la excepción original sin modificarla.
           [PROPÓSITO]: Permitir que el Backend (Laravel) capture el error y lo maneje
                        apropiadamente (logging, notificación al usuario, etc.).
           [ALTERNATIVA NO USADA]: Podríamos usar SIGNAL para generar un error personalizado,
                        pero perderíamos información valiosa del error original (código, mensaje).
           ------------------------------------------------------------------------------------- */
        RESIGNAL; 
    END;

    /* ===============================================================================================
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
       =============================================================================================== */
    
    /* -----------------------------------------------------------------------------------------------
       VALIDACIÓN 2.1: INTEGRIDAD DEL ID DE CAPACITACIÓN
       ----------------------------------------------------------------------------------------------- */
    /* [REGLA]     : El ID del expediente debe ser un entero positivo válido.
       [CASOS RECHAZADOS]:
         - NULL: El Frontend no envió el parámetro o lo envió vacío.
         - 0: Valor por defecto que indica "ningún registro seleccionado".
         - Negativos: Imposibles en una columna AUTO_INCREMENT.
       [CÓDIGO DE ERROR]: [400] Bad Request - Datos de entrada inválidos.
       [ACCIÓN DEL CLIENTE]: Debe verificar que se haya seleccionado un registro válido. */
    IF _Id_Capacitacion IS NULL OR _Id_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID de la Capacitación es inválido o nulo. Verifique que haya seleccionado un registro válido del listado.';
    END IF;

    /* -----------------------------------------------------------------------------------------------
       VALIDACIÓN 2.2: INTEGRIDAD DEL ID DE USUARIO EJECUTOR
       ----------------------------------------------------------------------------------------------- */
    /* [REGLA]     : El ID del usuario auditor debe ser un entero positivo válido.
       [CASOS RECHAZADOS]:
         - NULL: El Backend no extrajo correctamente el ID de la sesión.
         - 0 o negativos: Valores imposibles para un usuario autenticado.
       [CÓDIGO DE ERROR]: [400] Bad Request - Datos de entrada inválidos.
       [IMPLICACIÓN]: Sin este ID, no podemos registrar quién realizó la acción (auditoría rota).
       [ACCIÓN DEL CLIENTE]: El Backend debe verificar la sesión del usuario antes de llamar. */
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID del Usuario Ejecutor es obligatorio para la auditoría. Verifique la sesión del usuario autenticado.';
    END IF;

    /* -----------------------------------------------------------------------------------------------
       VALIDACIÓN 2.3: INTEGRIDAD Y DOMINIO DEL NUEVO ESTATUS
       ----------------------------------------------------------------------------------------------- */
    /* [REGLA]     : El parámetro de acción debe ser explícitamente 0 (Archivar) o 1 (Restaurar).
       [CASOS RECHAZADOS]:
         - NULL: El Frontend no especificó qué acción realizar.
         - Valores distintos de 0 o 1: Dominio no permitido (ej: 2, -1, 99).
       [CÓDIGO DE ERROR]: [400] Bad Request - Datos de entrada inválidos.
       [JUSTIFICACIÓN v2.0]: Este parámetro es NUEVO. Reemplaza el comportamiento "toggle" de v1.0
                             que infería la acción. Ahora requerimos intención explícita.
       [ACCIÓN DEL CLIENTE]: El Frontend debe enviar 0 para archivar o 1 para restaurar. */
    IF _Nuevo_Estatus IS NULL OR _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: El campo "Nuevo Estatus" es obligatorio y solo acepta valores binarios: 0 (Archivar) o 1 (Restaurar). Verifique el valor enviado.';
    END IF;

    /* ===============================================================================================
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
       =============================================================================================== */
    
    /* -----------------------------------------------------------------------------------------------
       CONSULTA 3.1: RADIOGRAFÍA DEL PADRE + DATOS DE AUDITORÍA
       -----------------------------------------------------------------------------------------------
       [OBJETIVO]    : Obtener el estado actual y los datos de identificación del expediente.
       [TABLAS]      : 
         - `Capacitaciones` (Padre): Estado actual, Folio.
         - `Cat_Gerencias_Activos` (Catálogo): Clave de la gerencia para auditoría.
       [JOIN]        : INNER JOIN porque la FK de gerencia es obligatoria (no puede haber huérfanos).
       [LIMIT 1]     : Optimización. Aunque el ID es único, LIMIT evita scans innecesarios.
       [INTO]        : Carga los resultados en variables locales para uso posterior.
       ----------------------------------------------------------------------------------------------- */
    SELECT 
        `Cap`.`Activo`,              -- Estado actual del expediente (1=Activo, 0=Archivado)
        `Cap`.`Numero_Capacitacion`, -- Folio para mensajes y auditoría
        `Ger`.`Clave`                -- Clave de gerencia para nota de auditoría
    INTO 
        v_Estado_Actual_Padre,       -- Variable: Estado actual
        v_Folio,                     -- Variable: Folio
        v_Clave_Gerencia             -- Variable: Gerencia
    FROM `Capacitaciones` `Cap`
    /* -----------------------------------------------------------------------------------------
       JOIN CON CATÁLOGO DE GERENCIAS
       -----------------------------------------------------------------------------------------
       [TIPO]   : INNER JOIN (obligatorio)
       [RAZÓN]  : Todo expediente DEBE tener una gerencia asignada (FK NOT NULL).
       [TABLA]  : Cat_Gerencias_Activos - Catálogo maestro de gerencias.
       [COLUMNA]: Clave - Identificador de negocio de la gerencia (ej: "GER-FINANZAS").
       ----------------------------------------------------------------------------------------- */
    INNER JOIN `Cat_Gerencias_Activos` `Ger` 
        ON `Cap`.`Fk_Id_CatGeren` = `Ger`.`Id_CatGeren`
    WHERE `Cap`.`Id_Capacitacion` = _Id_Capacitacion 
    LIMIT 1;

    /* -----------------------------------------------------------------------------------------------
       VALIDACIÓN 3.2: VERIFICACIÓN DE EXISTENCIA (404 NOT FOUND)
       -----------------------------------------------------------------------------------------------
       [REGLA]     : Si el SELECT no encontró registros, v_Estado_Actual_Padre será NULL.
       [CAUSA PROBABLE]:
         - El ID proporcionado nunca existió en la base de datos.
         - El registro fue eliminado físicamente (caso raro, DELETE está prohibido).
         - Error de sincronización entre Frontend y BD (cache desactualizado).
       [CÓDIGO DE ERROR]: [404] Not Found - Recurso no encontrado.
       [ACCIÓN DEL CLIENTE]: Refrescar la lista y seleccionar un registro válido.
       ----------------------------------------------------------------------------------------------- */
    IF v_Estado_Actual_Padre IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La Capacitación solicitada no existe en el catálogo maestro. Es posible que haya sido eliminada o que el ID sea incorrecto. Por favor, actualice su listado.';
    END IF;

    /* ===============================================================================================
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
       =============================================================================================== */
    IF v_Estado_Actual_Padre = _Nuevo_Estatus THEN
        /* -------------------------------------------------------------------------------------
           CONSTRUCCIÓN DEL MENSAJE DE IDEMPOTENCIA
           -------------------------------------------------------------------------------------
           [OBJETIVO]: Informar al usuario que no hubo cambios y por qué.
           [FORMATO] : Incluye el folio para que el usuario confirme que es el registro correcto.
           [TONO]    : Informativo (AVISO), no de error. No es un problema, solo una observación.
           ------------------------------------------------------------------------------------- */
        SELECT 
            CONCAT(
                'AVISO: La Capacitación "', v_Folio, '" ya se encuentra en el estado solicitado (', 
                IF(_Nuevo_Estatus = 1, 'ACTIVO', 'ARCHIVADO'), 
                '). No se realizaron cambios.'
            ) AS Mensaje, 
            'SIN_CAMBIOS' AS Accion;
        
        /* -------------------------------------------------------------------------------------
           SALIDA ANTICIPADA (EARLY EXIT)
           -------------------------------------------------------------------------------------
           [ACCIÓN]  : Terminar la ejecución del SP inmediatamente.
           [EFECTO]  : No se ejecuta ningún código posterior (transacción, UPDATEs, etc.).
           [NOTA]    : Esto es más limpio que usar flags booleanos y condicionales anidados.
           ------------------------------------------------------------------------------------- */
        LEAVE THIS_PROC;
    END IF;

    /* ===============================================================================================
       BLOQUE 5: RECUPERACIÓN DE DATOS DEL HIJO (DETALLE OPERATIVO)
       ===============================================================================================
       
       [PROPÓSITO]:
       Obtener información del registro hijo vigente (`DatosCapacitaciones`) que necesitamos para:
         1. Validar reglas de negocio (Es_Final).
         2. Saber qué registro actualizar.
         3. Inyectar la nota de auditoría.
       
       [CONTEXTO - ARQUITECTURA PADRE-HIJO]:
       Un expediente (`Capacitaciones`) puede tener múltiples versiones (`DatosCapacitaciones`).
       Cada vez que se edita un curso, se crea una nueva versión y se archiva la anterior.
       Solo la última versión (MAX ID) es la "vigente".
       
       [ESTRATEGIA - LATEST SNAPSHOT]:
       Usamos ORDER BY Id_DatosCap DESC LIMIT 1 para obtener siempre la versión más reciente.
       =============================================================================================== */
    SELECT 
        `DC`.`Id_DatosCap`,    -- ID del detalle vigente (para UPDATE posterior)
        `CatEst`.`Es_Final`,   -- Bandera de seguridad (¿Se puede archivar?)
        `CatEst`.`Nombre`      -- Nombre del estatus (para mensajes de error)
    INTO 
        v_Id_Ultimo_Detalle,   -- Variable: ID del hijo vigente
        v_Es_Estatus_Final,    -- Variable: Bandera Es_Final
        v_Nombre_Estatus       -- Variable: Nombre del estatus
    FROM `DatosCapacitaciones` `DC`
    /* -----------------------------------------------------------------------------------------
       JOIN CON CATÁLOGO DE ESTATUS
       -----------------------------------------------------------------------------------------
       [TIPO]   : INNER JOIN (obligatorio)
       [RAZÓN]  : Todo detalle DEBE tener un estatus asignado (FK NOT NULL).
       [TABLA]  : Cat_Estatus_Capacitacion - Catálogo maestro de estados del ciclo de vida.
       [COLUMNAS EXTRAÍDAS]:
         - Es_Final: Bandera que indica si el estatus permite archivado.
         - Nombre: Texto legible del estatus para mensajes de error.
       ----------------------------------------------------------------------------------------- */
    INNER JOIN `Cat_Estatus_Capacitacion` `CatEst` 
        ON `DC`.`Fk_Id_CatEstCap` = `CatEst`.`Id_CatEstCap`
    WHERE `DC`.`Fk_Id_Capacitacion` = _Id_Capacitacion
    /* -----------------------------------------------------------------------------------------
       ORDENAMIENTO PARA OBTENER LA VERSIÓN MÁS RECIENTE
       -----------------------------------------------------------------------------------------
       [ESTRATEGIA]: Los IDs son AUTO_INCREMENT, por lo que el ID más alto = versión más nueva.
       [ORDER BY]  : Descendente para que el primero sea el más reciente.
       [LIMIT 1]   : Solo necesitamos la versión vigente, no el historial completo.
       ----------------------------------------------------------------------------------------- */
    ORDER BY `DC`.`Id_DatosCap` DESC 
    LIMIT 1;

    /* ===============================================================================================
       BLOQUE 6: INICIO DE TRANSACCIÓN (ACID COMPLIANCE)
       ===============================================================================================
       
       [PROPÓSITO]:
       Iniciar un contexto transaccional que garantice atomicidad en las operaciones siguientes.
       
       [PRINCIPIO ACID - ATOMICIDAD]:
       Todas las operaciones dentro de esta transacción se ejecutan como una unidad indivisible:
         - O TODAS se completan exitosamente (COMMIT).
         - O NINGUNA se aplica (ROLLBACK).
       
       [OPERACIONES PROTEGIDAS]:
         1. UPDATE a `Capacitaciones` (Padre).
         2. UPDATE a `DatosCapacitaciones` (Hijo).
       
       [ESCENARIO DE FALLO]:
       Si el UPDATE al Padre tiene éxito pero el UPDATE al Hijo falla (ej: disco lleno),
       el ROLLBACK revierte AMBOS cambios, evitando inconsistencias.
       =============================================================================================== */
    START TRANSACTION;

    /* ===============================================================================================
       BLOQUE 7: MOTOR DE DECISIÓN - BIFURCACIÓN POR ACCIÓN SOLICITADA
       ===============================================================================================
       
       [PROPÓSITO]:
       Ejecutar la lógica específica según la acción solicitada:
         - _Nuevo_Estatus = 0: Ejecutar flujo de ARCHIVADO.
         - _Nuevo_Estatus = 1: Ejecutar flujo de RESTAURACIÓN.
       
       [ESTRUCTURA]:
       IF-ELSE con dos ramas mutuamente excluyentes.
       =============================================================================================== */

    /* ===========================================================================================
       RAMA A: FLUJO DE ARCHIVADO (_Nuevo_Estatus = 0)
       ===========================================================================================
       [OBJETIVO]: Cambiar el expediente de ACTIVO a ARCHIVADO (Soft Delete).
       [VALIDACIÓN REQUERIDA]: El estatus actual debe tener Es_Final = 1.
       [ACCIONES]:
         1. Validar regla de negocio (Es_Final = 1).
         2. Construir nota de auditoría.
         3. Apagar Padre (Activo = 0).
         4. Apagar Hijo + Inyectar nota (Activo = 0, Observaciones += nota).
       =========================================================================================== */
    IF _Nuevo_Estatus = 0 THEN
        
        /* ---------------------------------------------------------------------------------------
           PASO 7.A.1: CAPA 4 - VALIDACIÓN DE REGLAS DE NEGOCIO (BUSINESS RULES ENFORCEMENT)
           ---------------------------------------------------------------------------------------
           [REGLA]        : Solo se pueden archivar cursos con estatus TERMINAL (Es_Final = 1).
           [JUSTIFICACIÓN]: Archivar un curso "vivo" (en ejecución) lo haría desaparecer del
                            Dashboard sin haber completado su ciclo de vida, generando confusión.
           [ESTATUS PERMITIDOS]: FINALIZADO, CANCELADO, ARCHIVADO (Es_Final = 1).
           [ESTATUS BLOQUEADOS]: PROGRAMADO, EN CURSO, EVALUACIÓN, etc. (Es_Final = 0).
           --------------------------------------------------------------------------------------- */
        IF v_Es_Estatus_Final = 0 OR v_Es_Estatus_Final IS NULL THEN
            /* -----------------------------------------------------------------------------------
               ROLLBACK PREVENTIVO
               -----------------------------------------------------------------------------------
               [ACCIÓN] : Revertir la transacción antes de lanzar el error.
               [RAZÓN]  : Aunque no hemos hecho UPDATEs aún, es buena práctica cerrar la
                          transacción limpiamente antes de terminar el SP.
               ----------------------------------------------------------------------------------- */
            ROLLBACK;
            
            /* -----------------------------------------------------------------------------------
               CONSTRUCCIÓN DE MENSAJE DE ERROR DESCRIPTIVO
               -----------------------------------------------------------------------------------
               [OBJETIVO]: Dar al usuario información ACCIONABLE sobre cómo resolver el problema.
               [CONTENIDO]:
                 - Qué falló: "No se puede archivar un curso activo."
                 - Por qué: El estatus actual ("EN CURSO") es operativo, no final.
                 - Cómo resolverlo: "Debe finalizar o cancelar la capacitación antes."
               ----------------------------------------------------------------------------------- */
            SET @ErrorMsg = CONCAT(
                'ACCIÓN DENEGADA [409]: No se puede archivar un curso activo. ',
                'El estatus actual es "', v_Nombre_Estatus, '", el cual se considera OPERATIVO (No Final). ',
                'Debe finalizar o cancelar la capacitación antes de archivarla.'
            );
            
            /* -----------------------------------------------------------------------------------
               LANZAMIENTO DE EXCEPCIÓN CONTROLADA
               -----------------------------------------------------------------------------------
               [SQLSTATE 45000]: Código estándar para errores definidos por el usuario.
               [MESSAGE_TEXT] : El mensaje construido arriba.
               [EFECTO]       : El SP termina inmediatamente. El Backend captura este error.
               ----------------------------------------------------------------------------------- */
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @ErrorMsg;
        END IF;

        /* ---------------------------------------------------------------------------------------
           PASO 7.A.2: CONSTRUCCIÓN DE NOTA DE AUDITORÍA (AUDIT EVIDENCE PREPARATION)
           ---------------------------------------------------------------------------------------
           [PROPÓSITO]: Crear el texto que se inyectará en el campo Observaciones.
           [DATOS INCLUIDOS]:
             - Folio del curso (identificación).
             - Gerencia responsable (contexto organizacional).
             - Fecha y hora exacta (timestamp forense).
             - Motivo del archivado (justificación estándar).
           [FORMATO]: Texto plano con prefijo "[SISTEMA]:" para distinguirlo de notas manuales.
           --------------------------------------------------------------------------------------- */
        SET v_Mensaje_Auditoria = CONCAT(
            ' [SISTEMA]: La capacitación con folio ', v_Folio, 
            ' de la Gerencia ', v_Clave_Gerencia, 
            ', fue archivada el ', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), 
            ' porque alcanzó el fin de su ciclo de vida.'
        );

        /* ---------------------------------------------------------------------------------------
           PASO 7.A.3: CAPA 5 - EJECUCIÓN DE ARCHIVADO EN CASCADA (CASCADE SOFT DELETE)
           ---------------------------------------------------------------------------------------
           [ESTRATEGIA]: Actualizar Padre primero, luego Hijo.
           [RAZÓN DEL ORDEN]: Si fallara el UPDATE al Hijo, el ROLLBACK revertiría el Padre.
                              No importa el orden técnicamente, pero Padre→Hijo es más intuitivo.
           --------------------------------------------------------------------------------------- */
        
        /* -----------------------------------------------------------------------------------
           PASO 7.A.3.1: ARCHIVADO DEL PADRE (EXPEDIENTE MAESTRO)
           -----------------------------------------------------------------------------------
           [TABLA]   : Capacitaciones
           [CAMBIOS] :
             - Activo = 0: Marca el expediente como archivado (invisible en vistas operativas).
             - Fk_Id_Usuario_Cap_Updated_by: Registra quién realizó la acción (auditoría).
             - updated_at = NOW(): Registra cuándo se realizó la acción (timestamp).
           [FILTRO]  : WHERE Id_Capacitacion = _Id_Capacitacion (solo este expediente).
           ----------------------------------------------------------------------------------- */
        UPDATE `Capacitaciones` 
        SET 
            `Activo` = 0,                                        -- Soft Delete: Ocultar expediente
            `Fk_Id_Usuario_Cap_Updated_by` = _Id_Usuario_Ejecutor, -- Auditoría: Quién
            `updated_at` = NOW()                                  -- Auditoría: Cuándo
        WHERE `Id_Capacitacion` = _Id_Capacitacion;

        /* -----------------------------------------------------------------------------------
           PASO 7.A.3.2: ARCHIVADO DEL HIJO + INYECCIÓN DE NOTA (DETALLE OPERATIVO)
           -----------------------------------------------------------------------------------
           [TABLA]   : DatosCapacitaciones
           [CAMBIOS] :
             - Activo = 0: Marca la versión como archivada.
             - Fk_Id_Usuario_DatosCap_Updated_by: Registra quién realizó la acción.
             - updated_at = NOW(): Registra cuándo se realizó la acción.
             - Observaciones: CONCATENA la nota de auditoría con las observaciones existentes.
           [FILTRO]  : WHERE Id_DatosCap = v_Id_Ultimo_Detalle (solo la versión vigente).
           [NOTA SOBRE CONCAT_WS]:
             - WS = "With Separator". Agrega el separador SOLO si ambos valores no son NULL.
             - Separador '\n\n': Doble salto de línea para separar visualmente la nota.
             - Si Observaciones era NULL, solo quedará la nota de auditoría (sin separador).
           ----------------------------------------------------------------------------------- */
        UPDATE `DatosCapacitaciones` 
        SET 
            `Activo` = 0,                                                -- Soft Delete: Ocultar versión
            `Fk_Id_Usuario_DatosCap_Updated_by` = _Id_Usuario_Ejecutor,   -- Auditoría: Quién
            `updated_at` = NOW(),                                         -- Auditoría: Cuándo
            `Observaciones` = CONCAT_WS('\n\n', `Observaciones`, v_Mensaje_Auditoria) -- Inyección de nota
        WHERE `Id_DatosCap` = v_Id_Ultimo_Detalle;

        /* -----------------------------------------------------------------------------------
           PASO 7.A.4: CONFIRMACIÓN DE TRANSACCIÓN (COMMIT)
           -----------------------------------------------------------------------------------
           [ACCIÓN] : Hacer permanentes todos los cambios de esta transacción.
           [EFECTO] : Los UPDATEs se escriben definitivamente en disco.
           [PUNTO DE NO RETORNO]: Después del COMMIT, no hay ROLLBACK posible.
           ----------------------------------------------------------------------------------- */
        COMMIT;
        
        /* -----------------------------------------------------------------------------------
           PASO 7.A.5: RETORNO DE CONFIRMACIÓN AL CLIENTE
           -----------------------------------------------------------------------------------
           [FORMATO] : Resultset de fila única con 3 columnas.
           [USO]     : El Backend/Frontend usa estos valores para actualizar la UI.
           ----------------------------------------------------------------------------------- */
        SELECT 
            'ARCHIVADO' AS `Nuevo_Estado`,                                    -- Estado resultante
            'Expediente archivado y nota de auditoría registrada.' AS `Mensaje`, -- Feedback
            'ESTATUS_CAMBIADO' AS Accion;                                     -- Código de acción

    /* ===========================================================================================
       RAMA B: FLUJO DE RESTAURACIÓN (_Nuevo_Estatus = 1)
       ===========================================================================================
       [OBJETIVO]: Cambiar el expediente de ARCHIVADO a ACTIVO (Undelete).
       [VALIDACIÓN REQUERIDA]: Ninguna adicional. Si está archivado, siempre se puede restaurar.
       [ACCIONES]:
         1. Encender Padre (Activo = 1).
         2. Encender Hijo (Activo = 1).
       [NOTA]: No se inyecta nota de auditoría en la restauración. El timestamp en updated_at
               y el updated_by son suficientes para rastrear la acción.
       =========================================================================================== */
    ELSE
        /* ---------------------------------------------------------------------------------------
           PASO 7.B.1: RESTAURACIÓN DEL PADRE (EXPEDIENTE MAESTRO)
           ---------------------------------------------------------------------------------------
           [TABLA]   : Capacitaciones
           [CAMBIOS] :
             - Activo = 1: Reactiva el expediente (visible en vistas operativas nuevamente).
             - Fk_Id_Usuario_Cap_Updated_by: Registra quién realizó la restauración.
             - updated_at = NOW(): Registra cuándo se realizó la restauración.
           --------------------------------------------------------------------------------------- */
        UPDATE `Capacitaciones` 
        SET 
            `Activo` = 1,                                        -- Undelete: Mostrar expediente
            `Fk_Id_Usuario_Cap_Updated_by` = _Id_Usuario_Ejecutor, -- Auditoría: Quién
            `updated_at` = NOW()                                  -- Auditoría: Cuándo
        WHERE `Id_Capacitacion` = _Id_Capacitacion;

        /* ---------------------------------------------------------------------------------------
           PASO 7.B.2: RESTAURACIÓN DEL HIJO (DETALLE OPERATIVO)
           ---------------------------------------------------------------------------------------
           [TABLA]   : DatosCapacitaciones
           [CAMBIOS] :
             - Activo = 1: Reactiva la versión vigente.
             - Fk_Id_Usuario_DatosCap_Updated_by: Registra quién realizó la restauración.
             - updated_at = NOW(): Registra cuándo se realizó la restauración.
           [NOTA]    : NO se modifican las Observaciones. La nota de archivado anterior permanece
                       como evidencia histórica de que el expediente estuvo archivado.
           --------------------------------------------------------------------------------------- */
        UPDATE `DatosCapacitaciones` 
        SET 
            `Activo` = 1,                                                -- Undelete: Mostrar versión
            `Fk_Id_Usuario_DatosCap_Updated_by` = _Id_Usuario_Ejecutor,   -- Auditoría: Quién
            `updated_at` = NOW()                                          -- Auditoría: Cuándo
        WHERE `Id_DatosCap` = v_Id_Ultimo_Detalle;

        /* ---------------------------------------------------------------------------------------
           PASO 7.B.3: CONFIRMACIÓN DE TRANSACCIÓN (COMMIT)
           --------------------------------------------------------------------------------------- */
        COMMIT;
        
        /* ---------------------------------------------------------------------------------------
           PASO 7.B.4: RETORNO DE CONFIRMACIÓN AL CLIENTE
           --------------------------------------------------------------------------------------- */
        SELECT 
            'RESTAURADO' AS `Nuevo_Estado`,                       -- Estado resultante
            'Expediente restaurado exitosamente.' AS `Mensaje`,   -- Feedback
            'ESTATUS_CAMBIADO' AS Accion;                         -- Código de acción

    END IF;
    /* ===========================================================================================
       FIN DEL MOTOR DE DECISIÓN
       =========================================================================================== */

END$$

DELIMITER ;

/* ====================================================================================================
   FIN DEL PROCEDIMIENTO: SP_CambiarEstatusCapacitacion
   ====================================================================================================
   
   [RESUMEN DE IMPLEMENTACIÓN]:
   ✓ Validación de parámetros de entrada (Capa 1)
   ✓ Verificación de existencia del expediente (Capa 2)
   ✓ Control de idempotencia (Capa 3)
   ✓ Validación de reglas de negocio para archivado (Capa 4)
   ✓ Atomicidad transaccional (Capa 5)
   ✓ Cascada de actualización Padre→Hijo
   ✓ Inyección de nota de auditoría
   ✓ Handler de excepciones con rollback automático
   
   [PRUEBAS RECOMENDADAS]:
   1. Archivar un curso en estatus FINALIZADO (debe funcionar).
   2. Archivar un curso en estatus EN CURSO (debe fallar con [409]).
   3. Restaurar un curso archivado (debe funcionar).
   4. Archivar un curso ya archivado (debe retornar SIN_CAMBIOS).
   5. Llamar con ID inexistente (debe fallar con [404]).
   6. Llamar con parámetros NULL (debe fallar con [400]).
   
   ==================================================================================================== */