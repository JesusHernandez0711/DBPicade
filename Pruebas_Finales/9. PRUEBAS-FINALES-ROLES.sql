use Picade;

/* =================================================================================
   SCRIPT DE VALIDACIÓN (QA) - MÓDULO ROLES DE SISTEMA
   =================================================================================
   OBJETIVO:
   Validar la robustez, seguridad y lógica de negocio de la entidad `Cat_Roles`.
   
   ALCANCE DE PRUEBAS:
   1. Registro: Sanitización, Identidad Dual (Código/Nombre) y Autosanación.
   2. Lectura: Vistas abstractas y Consultas de detalle.
   3. Edición: Bloqueo de duplicados, Concurrencia y "Sin Cambios".
   4. Estatus (Soft Delete): Política de "Kill Switch" (Desactivar con usuarios).
   5. Eliminación Física (Hard Delete): Bloqueo estricto por dependencias.
   ================================================================================= */

/* ---------------------------------------------------------------------------------
   FASE 0: LIMPIEZA PREVIA (Para ambiente de pruebas)
   --------------------------------------------------------------------------------- */
-- DELETE FROM `Cat_Roles` WHERE `Codigo` LIKE 'ROL-QA%';
-- DELETE FROM `Usuarios` WHERE `Email` LIKE 'qa_%@test.com';

/* =================================================================================
   FASE 1: REGISTRO Y REGLAS DE UNICIDAD (HAPPY PATH & DIRTY DATA)
   Objetivo: Verificar creación, limpieza de strings y manejo de duplicados.
   ================================================================================= */

-- 1.1. Registro Exitoso con Datos Sucios (Espacios)
-- [ESPERADO]: Mensaje 'ÉXITO: Rol creado correctamente.', Accion 'CREADA'.
-- El sistema debe hacer TRIM automático.
CALL SP_RegistrarRol('  ROL-QA-01  ', '  ROL DE CALIDAD ALPHA  ', '  Descripcion con espacios  ');

-- Guardamos ID para pruebas posteriores
SET @IdRol1 = (SELECT Id_Rol FROM Cat_Roles WHERE Codigo = 'ROL-QA-01');

-- 1.2. Prueba de "Todo Obligatorio" (Intentar registrar NULLs)
-- [ESPERADO]: 🔴 ERROR [400]: "ERROR DE VALIDACIÓN: El campo CÓDIGO es obligatorio."
CALL SP_RegistrarRol(NULL, 'NOMBRE SIN CODIGO', 'DESC');

-- 1.3. Registro del Segundo Dato (Para pruebas cruzadas)
-- [ESPERADO]: Accion 'CREADA'.
CALL SP_RegistrarRol('ROL-QA-02', 'ROL DE CALIDAD BETA', 'Descripcion Beta');
SET @IdRol2 = (SELECT Id_Rol FROM Cat_Roles WHERE Codigo = 'ROL-QA-02');

-- 1.4. Prueba de Idempotencia por CÓDIGO (Re-enviar lo mismo del 1.1)
-- [ESPERADO]: Mensaje 'AVISO: El Rol ya existe...', Accion 'REUSADA'.
CALL SP_RegistrarRol('ROL-QA-01', 'ROL DE CALIDAD ALPHA', 'OTRA DESC');

-- 1.5. Conflicto de Identidad Cruzada (Mismo Código, diferente Nombre)
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE INTEGRIDAD: El CÓDIGO ya existe pero pertenece a un Rol con distinto NOMBRE."
CALL SP_RegistrarRol('ROL-QA-01', 'NOMBRE IMPOSTOR', 'DESC');

-- 1.6. Conflicto de Identidad Cruzada (Mismo Nombre, diferente Código)
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE INTEGRIDAD: El NOMBRE ya existe asociado a otro CÓDIGO diferente."
CALL SP_RegistrarRol('ROL-QA-99', 'ROL DE CALIDAD ALPHA', 'DESC');


/* =================================================================================
   FASE 2: LECTURA Y VISTAS
   Objetivo: Verificar que la UI reciba los datos correctos y limpios.
   ================================================================================= */

-- 2.1. Listado Admin (Vista Completa - Grid)
-- [ESPERADO]: Deben salir los 2 registros creados. Verificar columna 'Estatus_Rol'.
CALL SP_ListarRolesAdmin();

-- 2.2. Listado Activos (Dropdown Operativo)
-- [ESPERADO]: Solo ID, Código y Nombre. Deben salir ambos.
CALL SP_ListarRolesActivos();

-- 2.3. Consulta Específica (Para Edición - Raw Data)
-- [ESPERADO]: Datos crudos. Verificar fechas created_at/updated_at.
CALL SP_ConsultarRolEspecifico(@IdRol1);


/* =================================================================================
   FASE 3: EDICIÓN E INTEGRIDAD
   Objetivo: Verificar validaciones al modificar datos y bloqueos.
   ================================================================================= */

-- 3.1. Prueba "Sin Cambios" (Idempotencia en Update)
-- [ESPERADO]: Mensaje 'AVISO: No se detectaron cambios...', Accion 'SIN_CAMBIOS'.
CALL SP_EditarRol(@IdRol1, 'ROL-QA-01', 'ROL DE CALIDAD ALPHA', 'Descripcion con espacios');

-- 3.2. Prueba de Duplicidad Global (Robar código de otro)
-- Intentamos ponerle al Rol 2 el código del Rol 1.
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE DATOS: El CÓDIGO ingresado ya pertenece a otro Rol."
CALL SP_EditarRol(@IdRol2, 'ROL-QA-01', 'NOMBRE X', 'DESC');

-- 3.3. Prueba de Duplicidad Global (Robar nombre de otro)
-- Intentamos ponerle al Rol 2 el nombre del Rol 1.
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE DATOS: El NOMBRE ingresado ya pertenece a otro Rol."
CALL SP_EditarRol(@IdRol2, 'COD-X', 'ROL DE CALIDAD ALPHA', 'DESC');

-- 3.4. Edición Correcta (Evolución de datos)
-- Cambiamos nombre y descripción del Rol 2.
-- [ESPERADO]: Mensaje 'ÉXITO: Rol actualizado correctamente.', Accion 'ACTUALIZADA'.
CALL SP_EditarRol(@IdRol2, 'ROL-QA-02', 'ROL BETA EVOLUCIONADO', 'NUEVA DESCRIPCION');


/* =================================================================================
   FASE 4: ESTATUS Y POLÍTICA "KILL SWITCH"
   Objetivo: Verificar que se pueda desactivar AUNQUE haya usuarios (Seguridad > Integridad).
   ================================================================================= */

-- 4.1. Desactivar Rol 1 (Sin usuarios aún)
-- [ESPERADO]: Mensaje 'ÉXITO: Rol desactivado correctamente.', Accion 'CAMBIO_ESTATUS'.
CALL SP_CambiarEstatusRol(@IdRol1, 0);

-- 4.2. Verificar Listado Operativo
-- [ESPERADO]: El ROL-QA-01 NO debe aparecer en el dropdown (SP_ListarRolesActivos).
CALL SP_ListarRolesActivos();

-- 4.3. Reactivar Rol 1 (Para preparar la siguiente prueba)
-- [ESPERADO]: Mensaje 'ÉXITO: Rol reactivado correctamente.'.
CALL SP_CambiarEstatusRol(@IdRol1, 1);

/* ---------------------------------------------------------------------------------
   [SIMULACIÓN DE USUARIO ACTIVO]
   Creamos un usuario dummy asignado al Rol 1 para probar la política de seguridad.
   --------------------------------------------------------------------------------- */

-- A. Insertar Usuario Dummy vinculado al Rol 1 (@IdRol1)
-- (Usamos un InfoPersonal ficticio ID 1, asegurate que exista o usa uno válido)
INSERT INTO `Usuarios` (`Ficha`, `Email`, `Contraseña`, `Fk_Id_InfoPersonal`, `Fk_Rol`, `Activo`)
VALUES ('QA-USER-01', 'qa_test_rol@test.com', 'hash123', 1, @IdRol1, 1);

SET @IdUsuarioDummy = LAST_INSERT_ID();

-- 4.4. Intentar Desactivar Rol 1 con Usuario Activo
-- [ESPERADO]: ✅ ÉXITO. A diferencia de los catálogos geográficos, aquí DEBE PERMITIRLO.
-- Mensaje: 'ÉXITO: Rol desactivado correctamente.'
-- Esto confirma que el "Kill Switch" funciona para bloquear acceso masivo.
CALL SP_CambiarEstatusRol(@IdRol1, 0);

-- 4.5. Reactivar para limpieza
CALL SP_CambiarEstatusRol(@IdRol1, 1);


/* =================================================================================
   FASE 5: ELIMINACIÓN FÍSICA (HARD DELETE)
   Objetivo: Verificar que el borrado físico SÍ esté bloqueado por dependencias.
   ================================================================================= */

-- 5.1. Intentar Borrar Rol Inexistente
-- [ESPERADO]: 🔴 ERROR [404]: "ERROR DE NEGOCIO: El Rol que intenta eliminar no existe..."
CALL SP_EliminarRolFisicamente(999999);

/* ---------------------------------------------------------------------------------
   [PRUEBA DE CANDADO DE SEGURIDAD]
   El usuario dummy (@IdUsuarioDummy) existe y tiene el Rol 1.
   Por lo tanto, el sistema NO DEBE DEJAR BORRAR FISICAMENTE el rol.
   --------------------------------------------------------------------------------- */

-- 5.2. Intentar Borrar Rol 1 (Tiene usuario asignado)
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE SEGURIDAD: ...Existen USUARIOS registrados con este perfil..."
CALL SP_EliminarRolFisicamente(@IdRol1);

-- B. Limpieza del Usuario para permitir borrado (Solo para efectos de prueba)
DELETE FROM `Usuarios` WHERE `Id_Usuario` = @IdUsuarioDummy;

-- 5.3. Eliminación Física Exitosa - Rol 1
-- [ESPERADO]: 'ÉXITO: El Rol ha sido eliminado permanentemente...'
CALL SP_EliminarRolFisicamente(@IdRol1);

-- 5.4. Eliminación Física Exitosa - Rol 2
CALL SP_EliminarRolFisicamente(@IdRol2);

/* =================================================================================
   FIN DE LAS PRUEBAS - MÓDULO ROLES
   Si pasaste los errores rojos controlados, el módulo es seguro.
   ================================================================================= */