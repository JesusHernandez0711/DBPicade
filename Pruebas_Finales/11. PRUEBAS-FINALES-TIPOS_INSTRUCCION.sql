USE Picade;

/* =================================================================================
   SCRIPT DE VALIDACIÓN (QA) - MÓDULO TIPOS DE INSTRUCCIÓN
   =================================================================================
   OBJETIVO:
   Validar la robustez del módulo `Cat_Tipos_Instruccion_Cap`.
   
   ALCANCE DE PRUEBAS:
   1. Registro: Sanitización, Reglas de Unicidad y Autosanación.
   2. Lectura: Vistas Operativas vs Administrativas.
   3. Edición: Idempotencia, Bloqueo de Duplicados Cruzados.
   4. Estatus (Soft Delete): Candado de Integridad (No borrar si hay Cursos).
   5. Eliminación Física (Hard Delete): Bloqueo estricto por historial.
   ================================================================================= */

/* ---------------------------------------------------------------------------------
   FASE 0: LIMPIEZA PREVIA (Opcional, para entorno de pruebas limpio)
   --------------------------------------------------------------------------------- */
-- DELETE FROM Cat_Tipos_Instruccion_Cap WHERE Nombre LIKE '%PRUEBA QA%';

/* =================================================================================
   FASE 1: REGISTRO Y REGLAS DE INTEGRIDAD (HAPPY PATH & DIRTY DATA)
   Objetivo: Verificar creación, limpieza de strings y manejo de duplicados.
   ================================================================================= */

-- 1.1. Registro Exitoso con Datos Sucios (Espacios)
-- [ESPERADO]: Mensaje 'ÉXITO: Tipo... registrado correctamente', Accion 'CREADA'.
-- El sistema debe hacer TRIM automático.
CALL SP_RegistrarTipoInstruccion('  TEÓRICO PRUEBA QA  ', '  Requiere aula y proyector  ');

-- Guardamos ID para pruebas posteriores
SET @IdTipo1 = (SELECT Id_CatTipoInstCap FROM Cat_Tipos_Instruccion_Cap WHERE Nombre = 'TEÓRICO PRUEBA QA');

-- 1.2. Prueba de "Todo Obligatorio" (Intentar registrar NULL)
-- [ESPERADO]: 🔴 ERROR [400]: "ERROR DE VALIDACIÓN: El NOMBRE del Tipo de Instrucción es obligatorio."
CALL SP_RegistrarTipoInstruccion(NULL, 'Descripcion sin nombre');

-- 1.3. Registro del Segundo Dato (Para pruebas cruzadas)
-- [ESPERADO]: Accion 'CREADA'.
CALL SP_RegistrarTipoInstruccion('PRÁCTICO PRUEBA QA', 'Requiere taller o laboratorio');
SET @IdTipo2 = (SELECT Id_CatTipoInstCap FROM Cat_Tipos_Instruccion_Cap WHERE Nombre = 'PRÁCTICO PRUEBA QA');

-- 1.4. Prueba de Idempotencia (Re-enviar lo mismo del 1.1)
-- [ESPERADO]: Mensaje 'AVISO: El Tipo... ya existe...', Accion 'REUSADA'.
CALL SP_RegistrarTipoInstruccion('TEÓRICO PRUEBA QA', 'Otra descripción');


/* =================================================================================
   FASE 2: LECTURA Y VISTAS
   Objetivo: Verificar que la UI reciba los datos correctos y limpios.
   ================================================================================= */

-- 2.1. Listado Admin (Vista Completa - Grid)
-- [ESPERADO]: Deben salir los 2 registros creados. Verificar columna 'Estatus_Tipo_Instruccion'.
CALL SP_ListarTiposInstruccionAdmin();

-- 2.2. Listado Activos (Dropdown Operativo)
-- [ESPERADO]: Solo ID y Nombre. Deben salir ambos.
CALL SP_ListarTiposInstruccionActivos();

-- 2.3. Consulta Específica (Para Edición - Raw Data)
-- [ESPERADO]: Datos crudos. Verificar fechas created_at/updated_at.
CALL SP_ConsultarTipoInstruccionEspecifico(@IdTipo1);


/* =================================================================================
   FASE 3: EDICIÓN E INTEGRIDAD
   Objetivo: Verificar validaciones al modificar datos y bloqueos.
   ================================================================================= */

-- 3.1. Prueba "Sin Cambios" (Idempotencia en Update)
-- [ESPERADO]: Mensaje 'AVISO: No se detectaron cambios...', Accion 'SIN_CAMBIOS'.
CALL SP_EditarTipoInstruccion(@IdTipo1, 'TEÓRICO PRUEBA QA', 'Requiere aula y proyector');

-- 3.2. Prueba de Duplicidad Cruzada
-- Intentamos cambiar el nombre del Tipo 2 para que se llame como el Tipo 1.
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE DATOS: El NOMBRE ingresado ya pertenece a otro Tipo de Instrucción."
CALL SP_EditarTipoInstruccion(@IdTipo2, 'TEÓRICO PRUEBA QA', 'Intento de duplicado');

-- 3.3. Edición Correcta
-- Cambiamos nombre del Tipo 1.
-- [ESPERADO]: Mensaje 'ÉXITO: Tipo... actualizado correctamente.', Accion 'ACTUALIZADA'.
CALL SP_EditarTipoInstruccion(@IdTipo1, 'TEÓRICO AVANZADO QA', 'Nueva descripción');


/* =================================================================================
   FASE 4: ESTATUS Y CANDADOS DE INTEGRIDAD (SIMULACIÓN DE CURSOS)
   Objetivo: Verificar que no se pueda desactivar si hay cursos dependiendo de él.
   ================================================================================= */

-- 4.1. Desactivar Tipo 2 (Baja Lógica - Sin cursos aún)
-- [ESPERADO]: Mensaje 'ÉXITO: ...ha sido DESACTIVADO.', Accion 'ESTATUS_CAMBIADO'.
CALL SP_CambiarEstatusTipoInstruccion(@IdTipo2, 0);

-- 4.2. Verificar Listado Operativo
-- [ESPERADO]: El 'PRÁCTICO PRUEBA QA' NO debe aparecer en el dropdown (SP_ListarTiposInstruccionActivos).
CALL SP_ListarTiposInstruccionActivos();

-- 4.3. Reactivar Tipo 2 (Para preparar la siguiente prueba)
-- [ESPERADO]: Mensaje 'ÉXITO: ...ha sido REACTIVADO.'.
CALL SP_CambiarEstatusTipoInstruccion(@IdTipo2, 1);

/* ---------------------------------------------------------------------------------
   [SIMULACIÓN DE CANDADO DE NEGOCIO - CURSOS]
   Para esta prueba, necesitamos simular que existe un TEMA (Curso) usando este tipo.
   Como aún no creamos los SPs de Temas, haremos una inserción manual temporal controlada.
   --------------------------------------------------------------------------------- */

-- A. Insertar Tema Dummy vinculado al Tipo 1 (@IdTipo1)
INSERT INTO `Cat_Temas_Capacitacion` (`Nombre`, `Fk_Id_CatTipoInstCap`, `Activo`) 
VALUES ('CURSO DUMMY QA', @IdTipo1, 1);
SET @IdTemaDummy = LAST_INSERT_ID();

-- 4.4. Intentar Desactivar Tipo 1 con Curso Activo
-- [ESPERADO]: 🔴 ERROR [409]: "BLOQUEO DE INTEGRIDAD... existen CURSOS ACTIVOS asociados..."
CALL SP_CambiarEstatusTipoInstruccion(@IdTipo1, 0);

-- B. Liberar Candado (Simular que damos de baja el curso)
UPDATE `Cat_Temas_Capacitacion` SET `Activo` = 0 WHERE `Id_Cat_TemasCap` = @IdTemaDummy;

-- 4.5. Intentar Desactivar de nuevo (Ahora limpio de cursos activos)
-- [ESPERADO]: ÉXITO.
CALL SP_CambiarEstatusTipoInstruccion(@IdTipo1, 0);


/* =================================================================================
   FASE 5: ELIMINACIÓN FÍSICA (HARD DELETE)
   Objetivo: Limpieza final y prueba de los Anillos de Seguridad.
   ================================================================================= */

-- 5.1. Intentar Borrar Tipo Inexistente
-- [ESPERADO]: 🔴 ERROR [404]: "ERROR DE NEGOCIO: El Tipo de Instrucción... no existe."
CALL SP_EliminarTipoInstruccionFisico(999999);

/* ---------------------------------------------------------------------------------
   [PRUEBA DE CANDADO HISTÓRICO]
   El curso dummy (@IdTemaDummy) está Inactivo (Activo=0), pero EXISTE en la BD.
   Por lo tanto, NO DEBE DEJAR BORRAR FISICAMENTE el tipo, para no romper el historial.
   --------------------------------------------------------------------------------- */

-- 5.2. Intentar Borrar Tipo 1 (Tiene historial de cursos inactivos)
-- [ESPERADO]: 🔴 ERROR [409]: "BLOQUEO DE NEGOCIO... existen TEMAS DE CAPACITACIÓN (Activos o Históricos)..."
CALL SP_EliminarTipoInstruccionFisico(@IdTipo1);

-- C. Limpieza TOTAL del Histórico para permitir borrado (Solo para efectos de prueba)
DELETE FROM `Cat_Temas_Capacitacion` WHERE `Id_Cat_TemasCap` = @IdTemaDummy;

-- 5.3. Eliminación Física Exitosa - Tipo 1
-- [ESPERADO]: 'Registro eliminado permanentemente...'
CALL SP_EliminarTipoInstruccionFisico(@IdTipo1);

-- 5.4. Eliminación Física Exitosa - Tipo 2
CALL SP_EliminarTipoInstruccionFisico(@IdTipo2);

/* =================================================================================
   FIN DE LAS PRUEBAS - MÓDULO TIPOS DE INSTRUCCIÓN
   Si pasaste los errores rojos controlados, el módulo es DIAMOND STANDARD.
   ================================================================================= */