# Dockerfile del repositorio base.
# Contiene cinco malas practicas deliberadas. Cada una lleva su numero en la
# linea anterior. Corregirlas es el bloque A1 de la guia del laboratorio.
# Dockerfile corregido · INF384 Laboratorio 3 · bloque A1
#
# Hallazgo 1 -> imagen base con version fija (no :latest). Mismo commit, misma imagen.
#               Para fijarla aun mas, se puede usar el digest: nodejs:20@sha256:...
# Hallazgo 2 -> ya no se copia todo el contexto: solo manifiesto + lock, y luego src/.
#               El .dockerignore deja fuera .git, .env, node_modules, infra, etc.
# Hallazgo 3 -> npm ci instala exactamente lo del package-lock.json (falla si no cuadra).
# Hallazgo 4 -> sin credenciales: ninguna ENV/ARG con valores secretos.
#               Si la funcion necesitara una, se inyecta en el despliegue (Lambda), no aqui.
# Hallazgo 5 -> la etapa final no invoca dnf ni instala herramientas de depuracion.
#               Solo recibe el artefacto empaquetado dist/handler.js (sin node_modules).

# ---------- Etapa 1: build (tiene npm, dependencias de desarrollo y esbuild) ----------
FROM public.ecr.aws/lambda/nodejs:20.2024.05.01.10 AS build
WORKDIR /build

# Manifiesto y lock file ANTES del codigo: esta capa se reutiliza de la cache
# mientras package-lock.json no cambie.
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

# Recien ahora el codigo fuente, y se empaqueta con esbuild -> dist/handler.js
COPY src ./src
RUN npm run build

# ---------- Etapa 2: runtime (lo unico que viaja a produccion) ----------
FROM public.ecr.aws/lambda/nodejs:20.2024.05.01.10 AS runtime

# Solo el artefacto empaquetado. Nada de node_modules, nada de src/.
COPY --from=build /build/dist/handler.js ${LAMBDA_TASK_ROOT}/handler.js

# Forma exec: <archivo>.<funcion exportada>
CMD ["handler.handler"]
