#!/usr/bin/env bash
# =============================================================================
#  exam.sh  --  Simulacro de examen "Rank 04" (42)
#
#  Uso:  ./exam.sh
#
#  Modos:
#    real mode    -> recorre los niveles en orden (lvl1, lvl2, ...) y elige un
#                    ejercicio ALEATORIO de cada nivel. "cancel" sale del modo.
#    practice mode-> eliges nivel y ejercicio concretos.
#
#  Al arrancar un ejercicio:
#    * se crea ./rendu/<ejercicio>/ en el directorio de trabajo actual
#    * se copian los archivos (no directorios, no ocultos) de
#      resources/<nivel>/<ejercicio>/   [subject y, en vbc, given_code.c]
#    * se imprime el subject por terminal
#
#  Dentro del ejercicio solo existen dos comandos:
#    test   -> tests funcionales: compila tu codigo y la solucion con el mismo
#              main de pruebas, ejecuta la bateria de casos de cada ejercicio
#              y compara las salidas (stdout + codigo de salida) caso a caso.
#              Flags: -Wall -Wextra -Werror.
#    cancel -> abandona el ejercicio y vuelve al menu
#
#  Al terminar la sesion (quit, Ctrl-D o Ctrl-C) se elimina por completo
#  la carpeta rendu/ del directorio de trabajo.
# =============================================================================

set -u

# --- rutas -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCES="${SCRIPT_DIR}/resources"
RENDU="rendu"
PRAC_NEXT=""

# --- tests -------------------------------------------------------------------
CFLAGS=(-Wall -Wextra -Werror)
TIMEOUT_CMD=(timeout 5)
command -v timeout >/dev/null 2>&1 || TIMEOUT_CMD=()
TESTTMP=""      # directorio temporal del test en curso
TEST_INPUT=""   # stdin comun de toda la bateria
BAT_N=0         # contador de casos de la bateria

# --- colores -----------------------------------------------------------------
if [ -t 1 ]; then
	GRESET=$'\033[0m'
	GBOLD=$'\033[1m'
	GDIM=$'\033[2m'
	GRED=$'\033[31m'
	GGREEN=$'\033[32m'
	GYELLOW=$'\033[33m'
	GBLUE=$'\033[34m'
	GCYAN=$'\033[36m'
else
	GRESET=''; GBOLD=''; GDIM=''; GRED=''; GGREEN=''
	GYELLOW=''; GBLUE=''; GCYAN=''
fi

# --- limpieza al final de la sesion -------------------------------------------
# al salir del script (quit / Ctrl-D / Ctrl-C) se borra rendu/ entera
cleanup() {
	if [ -n "$TESTTMP" ] && [ -d "$TESTTMP" ]; then
		rm -rf -- "$TESTTMP"
		TESTTMP=""
	fi
	if [ -d "$RENDU" ]; then
		rm -rf -- "$RENDU"
		printf '\n%bsession finished%b: %s/ removed\n' \
			"$GYELLOW$GBOLD" "$GRESET" "$RENDU"
	fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# --- utilidades --------------------------------------------------------------

# trim de espacios/tabuladores por los extremos
trim() {
	local s=$1
	s="${s#"${s%%[![:space:]]*}"}"
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "$s"
}

# lee una linea en la variable REPLY.
#   -> devuelve 0 si la lee
#   -> devuelve 1 si la entrada se acaba (EOF)
#   -> termina la sesion (exit 130) si llega una senal (Ctrl-C)
ask() {
	local prompt=$1 st
	printf '%b' "$prompt"
	read -r REPLY
	st=$?
	if [ "$st" -eq 0 ]; then
		return 0
	fi
	printf '\n'
	REPLY=""
	if [ "$st" -ge 128 ]; then         # interrumpido por una senal
		printf '%bsession interrupted%s\n' "$GYELLOW$GBOLD" "$GRESET"
		exit 130
	fi
	return 1
}

# niveles existentes: resources/lvl*  (orden natural: lvl1, lvl2, ...)
list_levels() {
	local d
	for d in "$RESOURCES"/*/; do
		[ -d "$d" ] || continue
		basename "$d"
	done | sort -V
}

# ejercicios de un nivel (los directorios ocultos no cuentan)
list_exercises() {
	local lvl=$1 d
	for d in "$RESOURCES/$lvl"/*/; do
		[ -d "$d" ] || continue
		basename "$d"
	done | sort
}

# copia los archivos visibles del ejercicio a rendu/<ejercicio>
#   - no copia directorios (.solution se queda fuera)
#   - no copia archivos ocultos
#   - nunca pisa un archivo que ya exista en rendu (trabajo del alumno)
setup_exercise() {
	local lvl=$1 ex=$2
	local src="$RESOURCES/$lvl/$ex"
	local dst="$RENDU/$ex"
	local f base

	mkdir -p "$dst"
	for f in "$src"/* "$src"/.[!.]* "$src"/..?*; do
		[ -f "$f" ] || continue        # solo archivos
		base=$(basename "$f")
		case "$base" in .*) continue ;; esac   # nada oculto
		[ -e "$dst/$base" ] || cp "$f" "$dst/"
	done
}

# imprime el subject (o, en su defecto, los archivos copiados)
print_subject() {
	local lvl=$1 ex=$2
	local dst="$RENDU/$ex"

	printf '\n%b======== %s  /  %s ========%b\n' "$GBOLD$GBLUE" "$lvl" "$ex" "$GRESET"
	printf '%bexpected file:%b  %s.c\n' "$GYELLOW" "$GRESET" "$ex"
	printf '%blocation:%b      %s\n' "$GYELLOW" "$GRESET" "$dst"
	printf '%bcommands:%b      %btest%b  |  %bcancel%b\n\n' \
		"$GYELLOW" "$GRESET" "$GBOLD" "$GRESET" "$GBOLD" "$GRESET"

	if [ -f "$dst/subject.txt" ]; then
		cat "$dst/subject.txt"
	else
		local f
		for f in "$dst"/*; do
			[ -f "$f" ] || continue
			case "$(basename "$f")" in .*) continue ;; esac
			printf '\n%s\n' "$f"
			cat "$f"
		done
	fi
	printf '\n'
}

# fuentes visibles de un ejercicio (para compilar)
#   - si existe <ejercicio>.c se compilan todas las .c menos given_code.c
#   - si no, se compilan todas (caso de quien completa given_code.c)
collect_sources() {
	local dir=$1 ex=$2 f

	[ -d "$dir" ] || return 0
	if [ -f "$dir/$ex.c" ]; then
		for f in "$dir"/*.c; do
			[ -f "$f" ] || continue
			[ "${f##*/}" = "given_code.c" ] && continue
			printf '%s\n' "$f"
		done
	else
		for f in "$dir"/*.c; do
			[ -f "$f" ] && printf '%s\n' "$f"
		done
	fi
}

# =============================================================================
#  harness (main de pruebas) embebidos, uno por ejercicio
# =============================================================================

# main para ft_popen: ejercita 'r', 'w', el encadenado del subject, los
# errores y las fugas de file descriptors
harness_ft_popen() {
	cat > "$1" <<'HARNESS_EOF'
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

int	ft_popen(const char *file, char *const argv[], char type);

static int	count_fds(void)
{
	DIR				*dir;
	struct dirent	*entry;
	int				n = 0;

	dir = opendir("/proc/self/fd");
	if (!dir)
		return (-1);
	entry = readdir(dir);
	while (entry)
	{
		if (strcmp(entry->d_name, ".") && strcmp(entry->d_name, ".."))
			n++;
		entry = readdir(dir);
	}
	closedir(dir);
	return (n);
}

static void	drain(int fd)
{
	char	buffer[1024];
	ssize_t	size;

	size = read(fd, buffer, sizeof(buffer));
	while (size > 0)
	{
		if (write(STDOUT_FILENO, buffer, (size_t)size) < 0)
			break ;
		size = read(fd, buffer, sizeof(buffer));
	}
	close(fd);
}

static void	reap(void)
{
	while (wait(NULL) > 0)
		;
}

static void	case_r_echo(void)
{
	int	fd;

	fd = ft_popen("echo", (char *const []){"echo", "hello world", NULL}, 'r');
	printf("fd: %s\n", fd >= 0 ? "ok" : "-1");
	if (fd >= 0)
		drain(fd);
	reap();
}

static void	case_r_stdin(void)
{
	int	fd;

	fd = ft_popen("cat", (char *const []){"cat", NULL}, 'r');
	printf("fd: %s\n", fd >= 0 ? "ok" : "-1");
	if (fd >= 0)
		drain(fd);
	reap();
}

static void	case_r_chain(void)
{
	int	fd;

	fd = ft_popen("echo",
		(char *const []){"echo", "-e", "red\\ngreen\\nblue", NULL}, 'r');
	printf("first: %s\n", fd >= 0 ? "ok" : "-1");
	if (fd < 0)
	{
		reap();
		return ;
	}
	if (dup2(fd, STDIN_FILENO) < 0)
		printf("dup2 failed\n");
	close(fd);
	fd = ft_popen("grep", (char *const []){"grep", "e", NULL}, 'r');
	printf("second: %s\n", fd >= 0 ? "ok" : "-1");
	if (fd >= 0)
		drain(fd);
	reap();
}

static void	case_w_cat(void)
{
	int	fd;

	fd = ft_popen("cat", (char *const []){"cat", NULL}, 'w');
	printf("fd: %s\n", fd >= 0 ? "ok" : "-1");
	if (fd >= 0)
	{
		if (write(fd, "alpha\nbeta\n", 11) < 0)
			printf("write failed\n");
		close(fd);
	}
	reap();
}

static void	case_w_wc(void)
{
	int	fd;

	fd = ft_popen("wc", (char *const []){"wc", "-l", NULL}, 'w');
	printf("fd: %s\n", fd >= 0 ? "ok" : "-1");
	if (fd >= 0)
	{
		if (write(fd, "a\nb\nc\n", 6) < 0)
			printf("write failed\n");
		close(fd);
	}
	reap();
}

static void	case_err(void)
{
	char *const	argv[] = {"ls", NULL};

	printf("null file: %d\n", ft_popen(NULL, argv, 'r'));
	printf("null argv: %d\n", ft_popen("ls", NULL, 'r'));
	printf("type x: %d\n", ft_popen("ls", argv, 'x'));
	printf("type R: %d\n", ft_popen("ls", argv, 'R'));
	reap();
}

static void	case_missing(void)
{
	int	fd;

	fd = ft_popen("this_command_does_not_exist_42",
		(char *const []){"this_command_does_not_exist_42", NULL}, 'r');
	printf("fd: %s\n", fd >= 0 ? "ok" : "-1");
	if (fd >= 0)
		drain(fd);
	reap();
}

static void	case_leak(void)
{
	int	before;
	int	after;
	int	i;
	int	fd;

	before = count_fds();
	i = 0;
	while (i < 200)
	{
		fd = ft_popen("true", (char *const []){"true", NULL}, 'r');
		if (fd < 0)
			break ;
		close(fd);
		i++;
	}
	reap();
	after = count_fds();
	printf("fds: %d -> %d after %d iterations\n", before, after, i);
}

int	main(int argc, char **argv)
{
	const char	*name;

	setvbuf(stdout, NULL, _IONBF, 0);
	if (argc < 2)
		return (1);
	name = argv[1];
	if (!strcmp(name, "r_echo"))
		case_r_echo();
	else if (!strcmp(name, "r_stdin"))
		case_r_stdin();
	else if (!strcmp(name, "r_chain"))
		case_r_chain();
	else if (!strcmp(name, "w_cat"))
		case_w_cat();
	else if (!strcmp(name, "w_wc"))
		case_w_wc();
	else if (!strcmp(name, "err_args"))
		case_err();
	else if (!strcmp(name, "cmd_missing"))
		case_missing();
	else if (!strcmp(name, "fd_leak"))
		case_leak();
	else
		printf("unknown case\n");
	return (0);
}
HARNESS_EOF
}

# main para picoshell: monta cmds a partir de argv separado por "|" (igual
# que el main del examen) e imprime el valor devuelto
harness_picoshell() {
	cat > "$1" <<'HARNESS_EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int	picoshell(char **cmds[]);

int	main(int argc, char **argv)
{
	char	***cmds;
	int		ncmd;
	int		i;
	int		j;

	setvbuf(stdout, NULL, _IONBF, 0);
	ncmd = 1;
	for (i = 1; i < argc; i++)
	{
		if (!strcmp(argv[i], "|"))
			ncmd++;
	}
	cmds = calloc((size_t)ncmd + 1, sizeof(char **));
	if (!cmds)
		return (1);
	if (argc > 1)
	{
		cmds[0] = &argv[1];
		j = 0;
		for (i = 1; i < argc; i++)
		{
			if (!strcmp(argv[i], "|"))
			{
				argv[i] = NULL;
				j++;
				cmds[j] = &argv[i + 1];
			}
		}
	}
	printf("return: %d\n", picoshell(cmds));
	free(cmds);
	return (0);
}
HARNESS_EOF
}

# =============================================================================
#  baterias de casos: una por ejercicio
# =============================================================================

# ejecuta un caso y guarda stdout + codigo de salida en <dir>/NNN.out
run_case() {
	local bin=$1 dir=$2 name=$3 st f
	shift 3
	BAT_N=$((BAT_N + 1))
	f=$(printf '%s/%03d.out' "$dir" "$BAT_N")
	{
		printf '### case: %s\n' "$name"
		"${TIMEOUT_CMD[@]}" "$bin" "$@" < "$TEST_INPUT"
		st=$?
		printf '\n--- exit: %d\n' "$st"
	} > "$f"
}

battery_ft_popen() {
	local bin=$1 dir=$2 c
	BAT_N=0
	for c in r_echo r_stdin r_chain w_cat w_wc err_args cmd_missing fd_leak; do
		run_case "$bin" "$dir" "$c" "$c"
	done
}

battery_picoshell() {
	local bin=$1 dir=$2
	BAT_N=0
	run_case "$bin" "$dir" "echo"                     echo hello
	run_case "$bin" "$dir" "cat with our stdin"       cat
	run_case "$bin" "$dir" "2 commands"               /bin/echo hi "|" /usr/bin/cat
	run_case "$bin" "$dir" "3 commands"               echo one "|" cat "|" sed 's/o/0/'
	run_case "$bin" "$dir" "grep | wc"                echo x "|" grep x "|" wc -l
	run_case "$bin" "$dir" "big pipeline (1000 lines)" seq 1 1000 "|" wc -l
	run_case "$bin" "$dir" "printf | sort"            printf 'a\nb\n' "|" sort -r
	run_case "$bin" "$dir" "exit status is not an error" false
	run_case "$bin" "$dir" "command not found"        this_command_does_not_exist_42
	run_case "$bin" "$dir" "no command"
}

battery_vbc() {
	local bin=$1 dir=$2 expr
	BAT_N=0
	for expr in \
		"1" "0" "9" \
		"2+3" "3*4+5" "3+4*5" "2+3*4" "2*3+4" \
		"(3+4)*5" "(1)" "(((((((3)))))))" "(1+2)*3" \
		"(((1+2)))" "(((((((((9)))))))))" \
		"1+2+3+4+5" "1*2*3*4*5*6*7*8*9" "0*9" "9*9+1" \
		"(((((2+2)*2+2)*2+2)*2+2)*2+2)*2" \
		"((6*6+7+5+8)*(1+0+4*8+7)+2)+4*(1+2)" \
		"1+" "1+2)" "+1" "1++2" "(" ")" "2*" \
		"((1+3)*12+(3*(2+6))" "(1+2" "(1+2))" "*1" \
		"1+2+3*" "5*(3+2" "((1+2)*3" "9*(8+(7*6"
	do
		run_case "$bin" "$dir" "vbc '$expr'" "$expr"
	done
	run_case "$bin" "$dir" "vbc (empty expression)" ""
	run_case "$bin" "$dir" "vbc (no arguments)"
	run_case "$bin" "$dir" "vbc (too many arguments)" a b
}

# =============================================================================
#  ejecucion del test: compilar solucion + alumno, correr y comparar
# =============================================================================

# compara los dos directorios de resultados. 0 = success  1 = fail
compare_tests() {
	local sol_dir=$1 mine_dir=$2 tmp=$3
	local total=0 pass=0 base f name
	local failed=()
	local diff_file="$tmp/failed.diff"

	for f in "$sol_dir"/*.out; do
		[ -f "$f" ] || continue
		base=${f##*/}
		total=$((total + 1))
		if [ -f "$mine_dir/$base" ] && cmp -s "$f" "$mine_dir/$base"; then
			pass=$((pass + 1))
		else
			failed+=("$base")
		fi
	done

	if [ "$total" -eq 0 ]; then
		printf '%berror%b: no tests available for this exercise\n' \
			"$GRED$GBOLD" "$GRESET"
		return 1
	fi

	if [ "${#failed[@]}" -eq 0 ]; then
		printf '%b%bsuccess%b  %s(%d/%d tests)%s\n' \
			"$GGREEN" "$GBOLD" "$GRESET" "$GDIM" "$pass" "$total" "$GRESET"
		return 0
	fi

	printf '%b%bfail%b  %s(%d/%d tests)%s\n' \
		"$GRED" "$GBOLD" "$GRESET" "$GDIM" "$pass" "$total" "$GRESET"
	for base in "${failed[@]}"; do
		name=$(sed -n '1s/^### case: //p' "$sol_dir/$base")
		printf '  %b[ko]%b %s\n' "$GRED" "$GRESET" "$name"
	done

	: > "$diff_file"
	for base in "${failed[@]}"; do
		[ "$(wc -l < "$diff_file")" -ge 60 ] && break
		name=$(sed -n '1s/^### case: //p' "$sol_dir/$base")
		printf '### case: %s\n' "$name" >> "$diff_file"
		diff -u --label "expected (solution)" --label "yours" \
			"$sol_dir/$base" "$mine_dir/$base" >> "$diff_file" 2>/dev/null
		printf -- '---\n' >> "$diff_file"
	done
	printf '\n'
	head -n 60 "$diff_file"
	return 1
}

# fallback para ejercicios sin bateria: comparacion textual de los fuentes
textual_test() {
	local lvl=$1 ex=$2
	local mine="$RENDU/$ex/$ex.c"
	local ref="$RESOURCES/$lvl/$ex/.solution/$ex.c"
	local t_mine t_ref

	if [ ! -f "$mine" ]; then
		printf '%bfail%b: expected file not found: %s\n' \
			"$GRED$GBOLD" "$GRESET" "$mine"
		return 1
	fi
	t_mine=$(mktemp) && t_ref=$(mktemp) || return 1
	sed -e 's/\r$//' -e 's/[[:space:]]//g' -e '/^$/d' "$mine" > "$t_mine"
	sed -e 's/\r$//' -e 's/[[:space:]]//g' -e '/^$/d' "$ref" > "$t_ref"
	if cmp -s "$t_mine" "$t_ref"; then
		printf '%b%bsuccess%b  %s(no tests defined: source compared)%s\n' \
			"$GGREEN" "$GBOLD" "$GRESET" "$GDIM" "$GRESET"
		rm -f "$t_mine" "$t_ref"
		return 0
	fi
	printf '%b%bfail%b  %s(no tests defined: source compared)%s\n' \
		"$GRED" "$GBOLD" "$GRESET" "$GDIM" "$GRESET"
	diff -u --label "yours" --label "expected" "$t_mine" "$t_ref" | head -n 40
	rm -f "$t_mine" "$t_ref"
	return 1
}

# 0 = success   1 = fail
run_tests() {
	local lvl=$1 ex=$2
	local dir="$RENDU/$ex"
	local sol="$RESOURCES/$lvl/$ex/.solution"
	local tmp rc
	local -a srcs sol_srcs hsrc=()

	if ! declare -F "battery_$ex" >/dev/null 2>&1; then
		textual_test "$lvl" "$ex"
		return $?
	fi

	mapfile -t srcs < <(collect_sources "$dir" "$ex")
	if [ "${#srcs[@]}" -eq 0 ]; then
		printf '%bfail%b: no .c file found in %s/ (create %s.c)\n' \
			"$GRED$GBOLD" "$GRESET" "$dir" "$ex"
		return 1
	fi
	mapfile -t sol_srcs < <(collect_sources "$sol" "$ex")
	if [ "${#sol_srcs[@]}" -eq 0 ]; then
		printf '%berror%b: no solution found in %s\n' \
			"$GRED$GBOLD" "$GRESET" "$sol"
		return 1
	fi

	tmp=$(mktemp -d) || return 1
	TESTTMP="$tmp"
	TEST_INPUT="$tmp/input.txt"
	printf 'first line\nsecond line\nlast line\n' > "$TEST_INPUT"
	mkdir -p "$tmp/sol" "$tmp/mine"

	if [ "$ex" != "vbc" ]; then
		"harness_$ex" "$tmp/harness.c"
		hsrc=("$tmp/harness.c")
	fi

	if ! gcc "${CFLAGS[@]}" -I "$sol" -o "$tmp/sol.bin" \
		"${sol_srcs[@]}" "${hsrc[@]}" > "$tmp/sol.log" 2>&1; then
		printf '%berror%b: the reference solution does not compile\n' \
			"$GRED$GBOLD" "$GRESET"
		head -n 20 "$tmp/sol.log"
		rm -rf "$tmp"
		TESTTMP=""
		return 1
	fi

	if ! gcc "${CFLAGS[@]}" -I "$dir" -o "$tmp/mine.bin" \
		"${srcs[@]}" "${hsrc[@]}" > "$tmp/mine.log" 2>&1; then
		printf '%b%bfail%b  %scompilation error%s\n' \
			"$GRED" "$GBOLD" "$GRESET" "$GDIM" "$GRESET"
		head -n 30 "$tmp/mine.log"
		rm -rf "$tmp"
		TESTTMP=""
		printf '\nedit your file and type %btest%b again, or %bcancel%b\n' \
			"$GBOLD" "$GRESET" "$GBOLD" "$GRESET"
		return 1
	fi

	"battery_$ex" "$tmp/sol.bin" "$tmp/sol"
	"battery_$ex" "$tmp/mine.bin" "$tmp/mine"

	compare_tests "$tmp/sol" "$tmp/mine" "$tmp"
	rc=$?
	rm -rf "$tmp"
	TESTTMP=""
	if [ "$rc" -eq 0 ]; then
		return 0
	fi
	printf '\nedit your file and type %btest%b again, or %bcancel%b\n' \
		"$GBOLD" "$GRESET" "$GBOLD" "$GRESET"
	return 1
}

# --- bucle del ejercicio ------------------------------------------------------
# imprime el subject y deja el prompt hasta test (ok => 0) o cancel (=> 1)
exercise_loop() {
	local lvl=$1 ex=$2
	local cmd

	while true; do
		if ! ask $'\n> '; then
			printf '%bcancelled%b\n' "$GYELLOW" "$GRESET"
			return 1
		fi
		cmd=$(trim "$REPLY")
		cmd=${cmd,,}
		case "$cmd" in
			test)
				run_tests "$lvl" "$ex" && return 0
				;;
			cancel)
				printf '%bcancelled%b\n' "$GYELLOW" "$GRESET"
				return 1
				;;
			"")
				printf 'type %btest%b or %bcancel%b\n' \
					"$GBOLD" "$GRESET" "$GBOLD" "$GRESET"
				;;
			*)
				printf 'unknown command %b%s%b (test | cancel)\n' \
					"$GRED" "$cmd" "$GRESET"
				;;
		esac
	done
}

# monta el ejercicio completo. 0 = aprobado, 1 = cancelado
start_exercise() {
	local lvl=$1 ex=$2

	setup_exercise "$lvl" "$ex"
	print_subject "$lvl" "$ex"
	exercise_loop "$lvl" "$ex"
}

# --- modo real ---------------------------------------------------------------
real_mode() {
	local levels=()
	local passed=()
	local lvl ex i=0 n=0

	mapfile -t levels < <(list_levels)
	if [ "${#levels[@]}" -eq 0 ]; then
		printf '%bno levels found in %s%b\n' "$GRED" "$RESOURCES" "$GRESET"
		return
	fi

	printf '\n%b>> REAL MODE %s<<%b\n' "$GBOLD$GCYAN" \
		'(one random exercise per level)' "$GRESET"

	for lvl in "${levels[@]}"; do
		local exs=()
		mapfile -t exs < <(list_exercises "$lvl")
		[ "${#exs[@]}" -eq 0 ] && continue

		ex=${exs[$((RANDOM % ${#exs[@]}))]}
		i=$((i + 1))
		printf '\n%blevel %d/%d%s  ->  random pick: %b%s%b\n' \
			"$GYELLOW" "$i" "${#levels[@]}" "$GRESET" "$GBOLD" "$ex" "$GRESET"

		if start_exercise "$lvl" "$ex"; then
			passed+=("$lvl/$ex")
			n=$((n + 1))
			if [ "$i" -lt "${#levels[@]}" ]; then
				ask $'\npress ENTER for the next level... '
			fi
		else
			printf '\n%bEXAM ABORTED%s (cancel was typed)\n' \
				"$GRED$GBOLD" "$GRESET"
			return
		fi
	done

	printf '\n%b======== EXAM FINISHED ========%b\n' "$GBOLD$GGREEN" "$GRESET"
	if [ "$n" -eq 0 ]; then
		printf '%bno level passed%b\n' "$GRED" "$GRESET"
	else
		local p
		for p in "${passed[@]}"; do
			printf '  %b[ok]%b  %s\n' "$GGREEN" "$GRESET" "$p"
		done
	fi
	printf '%bscore: %d/%d levels%b\n' "$GBOLD" "$n" "${#levels[@]}" "$GRESET"
}

# --- modo practica -----------------------------------------------------------

# menu de seleccion de ejercicio de un nivel. sale con "q" al menu principal
practice_exercises() {
	local lvl=$1
	local exs=()
	local choice ex

	mapfile -t exs < <(list_exercises "$lvl")
	if [ "${#exs[@]}" -eq 0 ]; then
		printf '%bno exercises in %s%b\n' "$GRED" "$lvl" "$GRESET"
		return
	fi

	while true; do
		printf '\n%b-- %s --%b\n' "$GBOLD$GBLUE" "$lvl" "$GRESET"
		local k=1
		for ex in "${exs[@]}"; do
			printf '  %d) %s\n' "$k" "$ex"
			k=$((k + 1))
		done
		printf '  %bl%b choose another level\n' "$GCYAN" "$GRESET"
		printf '  %bq%b back to the main menu\n' "$GCYAN" "$GRESET"

		ask 'exercise> ' || { PRAC_NEXT="menu"; return; }
		choice=$(trim "$REPLY")
		case "$choice" in
			q|Q) PRAC_NEXT="menu"; return ;;
			l|L) PRAC_NEXT="level"; return ;;
			"") continue ;;
			*)
				if [[ "$choice" =~ ^[0-9]+$ ]] \
					&& [ "$choice" -ge 1 ] && [ "$choice" -le "${#exs[@]}" ]; then
					ex=${exs[$((choice - 1))]}
					practice_result "$lvl" "$ex"
					case "$PRAC_NEXT" in
						menu) return ;;
					esac
				else
					printf '%binvalid option%b\n' "$GRED" "$GRESET"
				fi
				;;
		esac
	done
}

# tras un success en practica se puede repetir el MISMO ejercicio, elegir
# otro o volver al menu principal.
# PRAC_NEXT al salir: other (otro ejercicio) | menu (menu principal)
practice_result() {
	local lvl=$1 ex=$2

	while true; do
		if ! start_exercise "$lvl" "$ex"; then
			PRAC_NEXT="other"      # cancel -> menu de seleccion de ejercicio
			return
		fi

		while true; do
			printf '\n[%b%s%b passed]  %bs%b repeat %s   %bo%b another exercise   %bm%b main menu\n' \
				"$GGREEN" "$ex" "$GRESET" "$GBOLD" "$GRESET" "$ex" \
				"$GBOLD" "$GRESET" "$GBOLD" "$GRESET"
			ask 'after test> ' || { PRAC_NEXT="other"; return; }
			case "$(trim "$REPLY")" in
				s|S) break ;;                      # repite el mismo
				o|O) PRAC_NEXT="other"; return ;;
				m|M) PRAC_NEXT="menu"; return ;;
				"") ;;
				*) printf '%binvalid option%b\n' "$GRED" "$GRESET" ;;
			esac
		done
	done
}

practice_mode() {
	local levels=()
	local choice lvl

	mapfile -t levels < <(list_levels)
	if [ "${#levels[@]}" -eq 0 ]; then
		printf '%bno levels found in %s%b\n' "$GRED" "$RESOURCES" "$GRESET"
		return
	fi

	printf '\n%b>> PRACTICE MODE %s<<%b\n' "$GBOLD$GCYAN" \
		'(pick any exercise)' "$GRESET"

	while true; do
		printf '\n%b-- levels --%b\n' "$GBOLD$GBLUE" "$GRESET"
		local k=1
		for lvl in "${levels[@]}"; do
			printf '  %d) %s\n' "$k" "$lvl"
			k=$((k + 1))
		done
		printf '  %bq%b back to the main menu\n' "$GCYAN" "$GRESET"

		ask 'level> ' || return
		choice=$(trim "$REPLY")
		case "$choice" in
			q|Q) return ;;
			"") continue ;;
			*)
				if [[ "$choice" =~ ^[0-9]+$ ]] \
					&& [ "$choice" -ge 1 ] && [ "$choice" -le "${#levels[@]}" ]; then
					lvl=${levels[$((choice - 1))]}
					PRAC_NEXT=""
					practice_exercises "$lvl"
					# "l" vuelve a elegir nivel, "q" sale del modo
					if [ "$PRAC_NEXT" = "menu" ]; then
						return
					fi
				else
					printf '%binvalid option%b\n' "$GRED" "$GRESET"
				fi
				;;
		esac
	done
}

# --- menu principal ----------------------------------------------------------
main_menu() {
	if [ ! -d "$RESOURCES" ]; then
		printf '%berror: resources not found at %s%b\n' \
			"$GRED" "$RESOURCES" "$GRESET"
		return 1
	fi

	while true; do
		printf '\n%b%b====================================%b\n' "$GBOLD" "$GCYAN" "$GRESET"
		printf '%b%b       EXAM RANK 04 - SIMULATOR%b\n' "$GBOLD" "$GCYAN" "$GRESET"
		printf '%b%b====================================%b\n' "$GBOLD" "$GCYAN" "$GRESET"
		printf '  1) real mode     %b(random exercise per level)%b\n' "$GDIM" "$GRESET"
		printf '  2) practice mode %b(choose the exercise)%b\n' "$GDIM" "$GRESET"
		printf '  0) quit\n'

		ask 'mode> ' || { printf '\nbye!\n'; return 0; }
		case "$(trim "$REPLY")" in
			1) real_mode ;;
			2) practice_mode ;;
			0|q|quit|exit) printf '\nbye!\n'; return 0 ;;
			"") ;;
			*) printf '%binvalid option%b\n' "$GRED" "$GRESET" ;;
		esac
	done
}

main_menu
