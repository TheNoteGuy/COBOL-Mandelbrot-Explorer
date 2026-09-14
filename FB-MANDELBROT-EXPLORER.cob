>>SOURCE FORMAT FREE
*>
*> CONTROLS
*>   Arrow keys or WASD  : pan
*>   + or =              : zoom in      - : zoom out
*>   [ / ]               : halve / double the iteration budget
*>   c                   : cycle palette stretch
*>   r                   : full-res render (any key aborts it or,
*>                          once it's done, returns to the preview)
*>   q                   : quit
*>
*> ENVIRONMENT
*>   MB_POLL=on|off        skip poll calibration, force it
*>   MB_FB=<path>          write frames somewhere other than
*>                         /dev/fb0 (a plain file works: raw BGRA)
*>   MB_KEYS=<keys>        play these keys instead of reading the
*>                         keyboard, then quit (testing without a
*>                         terminal; U/D/L/R stand in for arrows)
*>   MB_PREVIEW=<n>        pin the preview block size (2,3,4,5,
*>                         6,8,10 or 12) instead of adapting it
*>   MB_BRUTE=1            no rectangle subdivision (reference)
*>   MB_NOPERTURB=1        never use perturbation (reference;
*>                         wrong below 1e-11)
*>   MB_CENTER_X / MB_CENTER_Y / MB_HALF_WIDTH   starting view
*>   MB_DUMP=<path>        after every completed frame, write the
*>                         iteration count of every render pixel
*>                         to this text file (one header line,
*>                         then one count per line, row-major).
*>                         tests/verify.py diffs these against
*>                         frames computed at 256-bit precision.
*>
*> BUILD (-fnotrunc is REQUIRED; don't add -Wall, cobc 3.1.2
*> segfaults on the >>DEFINE lines with it)
*>   cobc -O2 -x -free -fnotrunc -o FB-MANDELBROT-EXPLORER \
*>       FB-MANDELBROT-EXPLORER.cob
*>
*> RUN (raw console, needs root for /dev/fb0)
*>   sudo sh -c 'export COB_TIMEOUT_SCALE=2; setterm -cursor off; \
*>       ./FB-MANDELBROT-EXPLORER; setterm -cursor on'

*> --- Screen geometry. Change these two and rebuild. ---
>>DEFINE CONSTANT SCREEN-WIDTH  AS 1920
>>DEFINE CONSTANT SCREEN-HEIGHT AS 1080

IDENTIFICATION DIVISION.
PROGRAM-ID. FB-MANDELBROT-EXPLORER.

ENVIRONMENT DIVISION.
CONFIGURATION SECTION.
SPECIAL-NAMES.
    CRT STATUS IS WS-CRT-STATUS.

INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT FRAMEBUFFER ASSIGN TO FB-PATH
        ORGANIZATION IS SEQUENTIAL
        FILE STATUS IS FB-STATUS.
    SELECT DUMPFILE ASSIGN TO DUMP-PATH
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS DUMP-STATUS.

DATA DIVISION.
FILE SECTION.
FD  FRAMEBUFFER.
01  FB-ROW.
    05  FB-PIXEL OCCURS SCREEN-WIDTH TIMES PIC X(4).
FD  DUMPFILE.
01  DUMP-REC               PIC X(160).

WORKING-STORAGE SECTION.
78  SCREEN-PIXELS          VALUE SCREEN-WIDTH * SCREEN-HEIGHT.
78  ITER-BUF-BYTES         VALUE SCREEN-PIXELS * 4.
78  ITER-UNSET             VALUE -1.
78  MAX-ITER-CAP           VALUE 50000.
78  ORBIT-ENTRIES          VALUE MAX-ITER-CAP + 2.
78  PAL-ITER-ENTRIES       VALUE 50002.
78  RECT-STACK-SIZE        VALUE 256.
78  MIN-SPLIT              VALUE 6.
*> delta stages: k runs 0..MAX-K, stored at index k + 1
78  MAX-K                  VALUE 40.
78  K-STEP                 VALUE 8.
*> hand a pixel to the direct loop once |delta| >= 100 * 10^-K-EXIT
*> (1e-7: 9 significant digits left in 16-decimal arithmetic, and
*> still far inside the escape radius, which the delta loop
*> doesn't check)
78  K-EXIT                 VALUE 9.

*> CRT-STATUS values for the arrow keys (see TROUBLESHOOTING).
01  COB-SCR-KEY-UP          PIC 9(4)  VALUE 2003.
01  COB-SCR-KEY-DOWN        PIC 9(4)  VALUE 2004.
01  COB-SCR-KEY-LEFT        PIC 9(4)  VALUE 2009.
01  COB-SCR-KEY-RIGHT       PIC 9(4)  VALUE 2010.

01  FB-STATUS              PIC XX.
01  FB-PATH                PIC X(256) VALUE "/dev/fb0".
01  DUMP-PATH              PIC X(256) VALUE SPACES.
01  DUMP-STATUS            PIC XX.
01  DUMP-ENABLED           PIC 9     VALUE 0.

*> --- Render geometry ---
01  RENDER-SCALE           PIC S9(8) COMP-5.
01  PREVIEW-SCALES.
    05  FILLER             PIC S9(8) COMP-5 VALUE 2.
    05  FILLER             PIC S9(8) COMP-5 VALUE 3.
    05  FILLER             PIC S9(8) COMP-5 VALUE 4.
    05  FILLER             PIC S9(8) COMP-5 VALUE 5.
    05  FILLER             PIC S9(8) COMP-5 VALUE 6.
    05  FILLER             PIC S9(8) COMP-5 VALUE 8.
    05  FILLER             PIC S9(8) COMP-5 VALUE 10.
    05  FILLER             PIC S9(8) COMP-5 VALUE 12.
01  PREVIEW-SCALE-TAB REDEFINES PREVIEW-SCALES.
    05  PREVIEW-SCALE-OF OCCURS 8 TIMES PIC S9(8) COMP-5.
01  PREVIEW-LEVEL          PIC S9(8) COMP-5 VALUE 3.
01  PREVIEW-PINNED         PIC 9     VALUE 0.
01  PREVIEW-SCALE          PIC S9(8) COMP-5 VALUE 4.
01  PREVIEW-SLOW-MS        PIC S9(9) COMP-5 VALUE 450.
01  PREVIEW-FAST-MS        PIC S9(9) COMP-5 VALUE 100.
01  RENDER-WIDTH           PIC S9(8) COMP-5.
01  RENDER-HEIGHT          PIC S9(8) COMP-5.
01  REGION-HEIGHT          PIC S9(8) COMP-5.
01  SYMMETRIC-FLAG         PIC 9     VALUE 0.
    88  VIEW-SYMMETRIC               VALUE 1.

*> --- Viewport, 38-digit decimal. SIGN LEADING SEPARATE gives
*> a plain "+dd.dddd" byte layout (without the point) that the
*> location parser/printer can work on directly. ---
01  HP-CENTER-X            PIC S9(2)V9(36) SIGN LEADING SEPARATE
                           VALUE -0.75.
01  HP-CENTER-X-B REDEFINES HP-CENTER-X PIC X(39).
01  HP-CENTER-Y            PIC S9(2)V9(36) SIGN LEADING SEPARATE
                           VALUE 0.
01  HP-CENTER-Y-B REDEFINES HP-CENTER-Y PIC X(39).
01  HP-HALF-WIDTH          PIC S9(2)V9(36) SIGN LEADING SEPARATE
                           VALUE 1.75.
01  HP-HALF-WIDTH-B REDEFINES HP-HALF-WIDTH PIC X(39).
01  HP-HALF-HEIGHT         PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HP-PAN-STEP-X          PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HP-PAN-STEP-Y          PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HP-REAL-MIN            PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HP-IMAG-MIN            PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HP-REAL-STEP           PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HP-IMAG-STEP           PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HP-TEMP                PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HP-TEMP-B REDEFINES HP-TEMP PIC X(39).
01  BASE-HALF-WIDTH        PIC S9(2)V9(36) SIGN LEADING SEPARATE
                           VALUE 1.75.
01  MIN-HALF-WIDTH         PIC S9(2)V9(36) SIGN LEADING SEPARATE
                           VALUE 0.000000000000000000000000000001.
01  MAX-HALF-WIDTH         PIC S9(2)V9(36) SIGN LEADING SEPARATE
                           VALUE 4.
01  MAX-CENTER             PIC S9(2)V9(36) SIGN LEADING SEPARATE
                           VALUE 4.
01  PERTURB-BELOW          PIC S9(2)V9(36) SIGN LEADING SEPARATE
                           VALUE 0.000000001.
01  BEST-SCAN-BELOW        PIC S9(2)V9(36) SIGN LEADING SEPARATE
                           VALUE 0.000001.

*> Per-column / per-row values of c (16 decimals; for the direct
*> loop and the cardioid pre-check), and the row base offsets.
01  CX-TABLE.
    05  CX-TAB OCCURS SCREEN-WIDTH TIMES  PIC S9(2)V9(16) COMP-5.
01  CY-TABLE.
    05  CY-TAB OCCURS SCREEN-HEIGHT TIMES PIC S9(2)V9(16) COMP-5.
01  ROW-BASE-TABLE.
    05  ROW-BASE-TAB OCCURS SCREEN-HEIGHT TIMES PIC S9(8) COMP-5.

*> --- Iteration budget ---
01  ITER-MULT-NUM          PIC S9(8) COMP-5 VALUE 4.
01  ITER-MULT-DEN          PIC S9(8) COMP-5 VALUE 4.
01  FULL-MAX-ITER          PIC S9(8) COMP-5 VALUE 50.
01  PREVIEW-MAX-ITER       PIC S9(8) COMP-5 VALUE 25.
01  CURRENT-MAX-ITER       PIC S9(8) COMP-5.
01  ZOOM-LOG2              USAGE COMP-2.
01  ITER-CALC              USAGE COMP-2.

*> --- Direct loop state ---
01  Z-PAIR.
    05  FZX                PIC S9(2)V9(16) COMP-5.
    05  FZY                PIC S9(2)V9(16) COMP-5.
01  Z-PAIR-RAW REDEFINES Z-PAIR.
    05  RZX                PIC S9(18) COMP-5.
    05  RZY                PIC S9(18) COMP-5.
01  Z-CHECK-PAIR           PIC X(16).
01  FZX2                   PIC S9(2)V9(16) COMP-5.
01  RZX2 REDEFINES FZX2    PIC S9(18) COMP-5.
01  FZY2                   PIC S9(2)V9(16) COMP-5.
01  RZY2 REDEFINES FZY2    PIC S9(18) COMP-5.
01  FCX                    PIC S9(2)V9(16) COMP-5.
01  FCY                    PIC S9(2)V9(16) COMP-5.
01  FZERO                  PIC S9(2)V9(16) COMP-5 VALUE 0.
01  FFOUR                  PIC S9(2)V9(16) COMP-5 VALUE 4.
01  RFOUR REDEFINES FFOUR  PIC S9(18) COMP-5.
01  FQ                     PIC S9(2)V9(16) COMP-5.
01  FQ-TERM                PIC S9(2)V9(16) COMP-5.
01  FTEST                  PIC S9(2)V9(16) COMP-5.
01  RTEST REDEFINES FTEST  PIC S9(18) COMP-5.
01  ITER                   USAGE INDEX.
01  MAX-ITER-IDX           USAGE INDEX.
01  NEXT-CHECK             USAGE INDEX.
01  ITER-RESULT            PIC S9(9) COMP-5.

*> --- Perturbation state ---
01  PERTURB-FLAG           PIC 9     VALUE 0.
    88  PERTURB                      VALUE 1.
*> reference point and its orbit
01  HP-REF-X               PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HP-REF-Y               PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HP-ORBIT-X             PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HP-ORBIT-Y             PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  ORBIT-VALID            PIC 9     VALUE 0.
01  ORBIT-LEN              PIC S9(8) COMP-5 VALUE 0.
01  ORBIT-ESCAPED          PIC 9     VALUE 0.
01  REF-ESC-IDX            PIC S9(8) COMP-5.
01  HZX                    PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HZY                    PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HZX2                   PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HZY2                   PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  ORBIT-I                PIC S9(8) COMP-5.
*> Z_n at 16 decimals (hot loop), |Z_n|^2 (rebase prefilter),
*> and Z_n at full precision (rebase itself). Index n + 1.
01  ZXR-TABLE.
    05  ZXR OCCURS ORBIT-ENTRIES TIMES PIC S9(2)V9(16) COMP-5.
01  ZYR-TABLE.
    05  ZYR OCCURS ORBIT-ENTRIES TIMES PIC S9(2)V9(16) COMP-5.
01  ZMAGR-TABLE.
    05  ZMAGR OCCURS ORBIT-ENTRIES TIMES PIC S9(2)V9(16) COMP-5.
01  RZMAGR-TABLE REDEFINES ZMAGR-TABLE.
    05  RZMAGR OCCURS ORBIT-ENTRIES TIMES PIC S9(18) COMP-5.
01  HP-ZXR-TABLE.
    05  HP-ZXR OCCURS ORBIT-ENTRIES TIMES
                           PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HP-ZYR-TABLE.
    05  HP-ZYR OCCURS ORBIT-ENTRIES TIMES
                           PIC S9(2)V9(36) SIGN LEADING SEPARATE.
*> best (highest iteration count) pixel of the last frame
01  BEST-VALID             PIC 9     VALUE 0.
01  BEST-ITER              PIC S9(8) COMP-5.
01  BEST-IDX               PIC S9(8) COMP-5.
01  BEST-PX                PIC S9(8) COMP-5.
01  BEST-PY                PIC S9(8) COMP-5.
01  HP-BEST-X              PIC S9(2)V9(36) SIGN LEADING SEPARATE.
01  HP-BEST-Y              PIC S9(2)V9(36) SIGN LEADING SEPARATE.
*> delta stage constants: 10^-k as TA(k) * TB(k), 10^k, and the
*> rebase prefilter bound (2 * sqrt(2) * 100 * 10^-k)^2
01  TA-TABLE.
    05  TA-TAB OCCURS 41 TIMES PIC SV9(18) COMP-5.
01  TB-TABLE.
    05  TB-TAB OCCURS 41 TIMES PIC S9(1)V9(17) COMP-5.
01  TENK-TABLE.
    05  TENK-TAB OCCURS 41 TIMES PIC 9(38).
01  ZLIM-TABLE.
    05  ZLIM-TAB OCCURS 41 TIMES PIC S9(2)V9(16) COMP-5.
01  K0                     PIC S9(8) COMP-5.
01  K-CUR                  PIC S9(8) COMP-5.
01  K-LOG                  USAGE COMP-2.
01  TA                     PIC SV9(18) COMP-5.
01  TB                     PIC S9(1)V9(17) COMP-5.
01  ZLIM                   PIC S9(2)V9(16) COMP-5.
01  RZLIM REDEFINES ZLIM   PIC S9(18) COMP-5.
01  RESCALE-FACTOR         PIC SV9(18) COMP-5.
01  K-DROP                 PIC S9(8) COMP-5.
01  DELTA-LIMIT            PIC S9(2)V9(16) COMP-5 VALUE 100.
01  RLIM REDEFINES DELTA-LIMIT PIC S9(18) COMP-5.
01  DELTA-NEG-LIMIT        PIC S9(2)V9(16) COMP-5 VALUE -100.
01  RNLIM REDEFINES DELTA-NEG-LIMIT PIC S9(18) COMP-5.
*> per-pixel delta state (D = delta * 10^k)
01  DX                     PIC S9(2)V9(16) COMP-5.
01  RDX REDEFINES DX       PIC S9(18) COMP-5.
01  DY                     PIC S9(2)V9(16) COMP-5.
01  RDY REDEFINES DY       PIC S9(18) COMP-5.
01  DXN                    PIC S9(2)V9(16) COMP-5.
01  D0X                    PIC S9(2)V9(16) COMP-5.
01  D0Y                    PIC S9(2)V9(16) COMP-5.
01  ZTX                    PIC S9(2)V9(16) COMP-5.
01  ZTY                    PIC S9(2)V9(16) COMP-5.
01  REF-IDX                PIC S9(8) COMP-5.
01  DELTA-DONE             PIC 9.
01  D0X-TABLE.
    05  D0X-TAB OCCURS SCREEN-WIDTH TIMES  PIC S9(2)V9(16) COMP-5.
01  D0Y-TABLE.
    05  D0Y-TAB OCCURS SCREEN-HEIGHT TIMES PIC S9(2)V9(16) COMP-5.

*> --- Per-frame pixel cache ---
01  ITER-BUF.
    05  ITER-CELL OCCURS SCREEN-PIXELS TIMES PIC S9(9) COMP-5.
01  ITER-BUF-B REDEFINES ITER-BUF PIC X(ITER-BUF-BYTES).

*> --- Rectangle work stack ---
01  RECT-STACK.
    05  RECT OCCURS RECT-STACK-SIZE TIMES.
        10  RS-X0          PIC S9(8) COMP-5.
        10  RS-Y0          PIC S9(8) COMP-5.
        10  RS-X1          PIC S9(8) COMP-5.
        10  RS-Y1          PIC S9(8) COMP-5.
01  RECT-TOP               PIC S9(8) COMP-5 VALUE 0.
01  CUR-RECT.
    05  CR-X0              PIC S9(8) COMP-5.
    05  CR-Y0              PIC S9(8) COMP-5.
    05  CR-X1              PIC S9(8) COMP-5.
    05  CR-Y1              PIC S9(8) COMP-5.
01  CR-W                   PIC S9(8) COMP-5.
01  CR-H                   PIC S9(8) COMP-5.
01  CR-MID                 PIC S9(8) COMP-5.
01  BORDER-VALUE           PIC S9(9) COMP-5.
01  BORDER-SAME-FLAG       PIC 9.
    88  BORDER-UNIFORM               VALUE 1.

*> --- Pixel addressing scratch ---
01  PX                     PIC S9(8) COMP-5.
01  PY                     PIC S9(8) COMP-5.
01  P-IDX                  PIC S9(8) COMP-5.
01  P-LEN                  PIC S9(8) COMP-5.
01  P-OFF                  PIC S9(8) COMP-5.
01  P-OFF2                 PIC S9(8) COMP-5.
01  FILL-ROW-START         PIC S9(8) COMP-5.
01  FILL-ROW-BYTES         PIC S9(8) COMP-5.
01  OUT-COL                PIC S9(8) COMP-5.
01  BLIT-ROW               PIC S9(8) COMP-5.
01  BLIT-COL               PIC S9(8) COMP-5.
01  ROWS-WRITTEN           PIC S9(8) COMP-5.

*> --- Statistics ---
01  PIXELS-COMPUTED        PIC S9(9) COMP-5.
01  PIXELS-FILLED          PIC S9(9) COMP-5.
01  RECTS-DONE             PIC S9(9) COMP-5.
01  REBASES                PIC S9(9) COMP-5.
01  DELTA-EXITS            PIC S9(9) COMP-5.
01  FRAME-START-CS         PIC S9(9) COMP-5.
01  FRAME-MS               PIC S9(9) COMP-5.
01  NUM-OUT                PIC -(9)9.
01  NUM-OUT2               PIC -(9)9.
01  NUM-OUT3               PIC -(9)9.
01  NUM-OUT4               PIC -(9)9.

*> --- Keyboard / navigation state ---
01  WS-CRT-STATUS          PIC 9(4)  VALUE 0.
01  WS-KEY                 PIC X.
01  QUIT-FLAG              PIC 9     VALUE 0.
    88  SHOULD-QUIT                  VALUE 1.
01  REAL-KEY-FLAG          PIC 9     VALUE 0.
    88  REAL-KEY                     VALUE 1.
01  SCRIPT-KEYS            PIC X(1024) VALUE SPACES.
01  SCRIPT-POS             PIC S9(8) COMP-5 VALUE 0.
01  SCRIPT-MODE            PIC 9     VALUE 0.
    88  SCRIPTED                     VALUE 1.
01  BRUTE-MODE             PIC 9     VALUE 0.
    88  BRUTE-FORCE                  VALUE 1.
01  NO-PERTURB-MODE        PIC 9     VALUE 0.

*> --- Mid-render interrupt polling (see CALIBRATE-POLL) ---
01  TIMEOUT-TICKS          PIC S9(8) COMP-5 VALUE 1.
01  MAX-TIMEOUT-TICKS      PIC S9(8) COMP-5 VALUE 8.
01  BREAK-RENDER           PIC 9     VALUE 0.
01  GOT-INPUT-FLAG         PIC 9     VALUE 0.
    88  GOT-MIDFRAME-INPUT           VALUE 1.
01  POLL-ENABLED           PIC 9     VALUE 0.
01  POLL-ACTIVE            PIC 9     VALUE 0.
01  POLL-EVERY-PIXELS      PIC S9(8) COMP-5 VALUE 4000.
01  PIXELS-SINCE-POLL      PIC S9(8) COMP-5 VALUE 0.

*> --- Poll calibration (centiseconds) ---
01  CALIB-REPS             PIC S9(8) COMP-5 VALUE 5.
01  TARGET-POLL-CS         PIC S9(8) COMP-5 VALUE 1.
01  MAX-POLL-COST-CS       PIC S9(8) COMP-5 VALUE 5.
01  FRAME-POLL-BUDGET-CS   PIC S9(8) COMP-5 VALUE 10.
01  POLLS-PER-FRAME        PIC S9(8) COMP-5 VALUE 8.
01  MAX-POLLS-PER-FRAME    PIC S9(8) COMP-5 VALUE 32.
01  CALIB-I                PIC S9(8) COMP-5.
01  CALIB-DIRTY            PIC 9     VALUE 0.
01  TICK-TOTAL-CS          PIC S9(9) COMP-5 VALUE 0.
01  TICK-COST-CS           PIC S9(9) COMP-5 VALUE 0.
01  POLL-COST-CS           PIC S9(9) COMP-5 VALUE 0.
01  MEASURED-TOTAL-CS      PIC S9(9) COMP-5 VALUE 0.
01  T-START                PIC S9(9) COMP-5 VALUE 0.
01  ENV-VALUE              PIC X(1024) VALUE SPACES.

*> --- Location parser scratch ---
01  LOC-IN                 PIC X(64).
01  LOC-MANT               PIC X(64).
01  LOC-EXP                PIC X(16).
01  LOC-INT                PIC X(16).
01  LOC-FRAC               PIC X(36).
01  LOC-SIGN               PIC X.
01  LOC-INT-NUM            PIC 99.
01  LOC-EXP-NUM            PIC S9(4).
01  LOC-I                  PIC S9(8) COMP-5.
01  LOC-OK                 PIC 9.
*> result of CARDIOID-CHECK
01  INSIDE-FLAG            PIC 9.
    88  INSIDE-CARDIOID-OR-BULB      VALUE 1.
*> CHOOSE-REFERENCE: use last frame's best pixel?
01  USE-BEST-FLAG          PIC 9.

01  NOW-STAMP.
    05  NOW-YMD            PIC X(8).
    05  NOW-HH             PIC 9(2).
    05  NOW-MI             PIC 9(2).
    05  NOW-SS             PIC 9(2).
    05  NOW-CS             PIC 9(2).
    05  FILLER             PIC X(5).
01  NOW-TOTAL-CS           PIC S9(9) COMP-5 VALUE 0.

*> --- Palette ---
01  PALETTE-TABLE.
    05  PAL-ENTRY OCCURS 17 TIMES.
        10  PAL-RED        PIC 9(3).
        10  PAL-GREEN      PIC 9(3).
        10  PAL-BLUE       PIC 9(3).
*> the expanded cycle: 16 * PAL-STRETCH interpolated colours
01  PAL-STRETCH            PIC S9(8) COMP-5 VALUE 1.
01  PAL-CYCLE-LEN          PIC S9(8) COMP-5 VALUE 16.
01  PAL-CYCLE-TABLE.
    05  PAL-CYCLE OCCURS 256 TIMES PIC X(4).
01  PAL-BY-ITER-TABLE.
    05  PAL-BY-ITER OCCURS PAL-ITER-ENTRIES TIMES PIC X(4).
01  BLACK-PIXEL            PIC X(4) VALUE X"00000000".
01  UNSET-PIXEL            PIC X(4) VALUE X"20202000".
01  PIXEL-BUILD.
    05  PB-BLUE            USAGE BINARY-CHAR UNSIGNED.
    05  PB-GREEN           USAGE BINARY-CHAR UNSIGNED.
    05  PB-RED             USAGE BINARY-CHAR UNSIGNED.
    05  PB-ALPHA           USAGE BINARY-CHAR UNSIGNED.
01  PAL-I                  PIC S9(8) COMP-5.
01  PAL-J                  PIC S9(8) COMP-5.
01  PAL-A                  PIC S9(8) COMP-5.
01  PAL-T                  PIC S9(8) COMP-5.
01  PAL-C                  PIC S9(8) COMP-5.

PROCEDURE DIVISION.
MAIN-LOGIC.
    PERFORM LOAD-PALETTE.
    PERFORM BUILD-STAGE-TABLES.
    PERFORM READ-ENVIRONMENT.

    SET ENVIRONMENT "COB_SCREEN_EXCEPTIONS" TO "Y".
    SET ENVIRONMENT "COB_SCREEN_ESC" TO "Y".
    SET ENVIRONMENT "COB_TIMEOUT_SCALE" TO "2".

    DISPLAY "Mandelbrot Explorer 11".
    DISPLAY "  Arrow keys or WASD : pan".
    DISPLAY "  + / -              : zoom in / out".
    DISPLAY "  [ / ]              : fewer / more iterations".
    DISPLAY "  c                  : palette stretch".
    DISPLAY "  r                  : full-res render (any key aborts)".
    DISPLAY "  q                  : quit".

    IF SCRIPTED
        MOVE 0 TO POLL-ENABLED
    ELSE
        PERFORM CALIBRATE-POLL
    END-IF.

    MOVE SPACE TO WS-KEY.
    MOVE 0 TO WS-CRT-STATUS.
    MOVE 0 TO REAL-KEY-FLAG.

    PERFORM UNTIL SHOULD-QUIT
        MOVE PREVIEW-SCALE TO RENDER-SCALE
        PERFORM COMPUTE-VIEWPORT
        PERFORM RENDER-FRAME
        PERFORM ADAPT-PREVIEW-SCALE
        IF SCRIPTED
            PERFORM SHOW-FRAME-STATS
        END-IF
        IF NOT GOT-MIDFRAME-INPUT
            PERFORM READ-KEY
        END-IF
        PERFORM HANDLE-KEY
    END-PERFORM.

    PERFORM SHOW-LOCATION.
    DISPLAY "Bye.".
    STOP RUN.

ADAPT-PREVIEW-SCALE.
    IF PREVIEW-PINNED = 1
        EXIT PARAGRAPH
    END-IF.
    IF FRAME-MS > PREVIEW-SLOW-MS OR GOT-MIDFRAME-INPUT
        IF PREVIEW-LEVEL < 8
            ADD 1 TO PREVIEW-LEVEL
        END-IF
    ELSE
        IF FRAME-MS < PREVIEW-FAST-MS AND PREVIEW-LEVEL > 1
            SUBTRACT 1 FROM PREVIEW-LEVEL
        END-IF
    END-IF.
    MOVE PREVIEW-SCALE-OF(PREVIEW-LEVEL) TO PREVIEW-SCALE.

READ-ENVIRONMENT.
    MOVE SPACES TO ENV-VALUE.
    ACCEPT ENV-VALUE FROM ENVIRONMENT "MB_FB"
        ON EXCEPTION MOVE SPACES TO ENV-VALUE
    END-ACCEPT.
    IF ENV-VALUE NOT = SPACES
        MOVE ENV-VALUE TO FB-PATH
    END-IF.

    MOVE SPACES TO ENV-VALUE.
    ACCEPT ENV-VALUE FROM ENVIRONMENT "MB_DUMP"
        ON EXCEPTION MOVE SPACES TO ENV-VALUE
    END-ACCEPT.
    IF ENV-VALUE NOT = SPACES
        MOVE ENV-VALUE TO DUMP-PATH
        MOVE 1 TO DUMP-ENABLED
    END-IF.

    MOVE SPACES TO ENV-VALUE.
    ACCEPT ENV-VALUE FROM ENVIRONMENT "MB_KEYS"
        ON EXCEPTION MOVE SPACES TO ENV-VALUE
    END-ACCEPT.
    IF ENV-VALUE NOT = SPACES
        MOVE ENV-VALUE TO SCRIPT-KEYS
        MOVE 1 TO SCRIPT-MODE
        MOVE 0 TO SCRIPT-POS
    END-IF.

    MOVE SPACES TO ENV-VALUE.
    ACCEPT ENV-VALUE FROM ENVIRONMENT "MB_BRUTE"
        ON EXCEPTION MOVE SPACES TO ENV-VALUE
    END-ACCEPT.
    IF ENV-VALUE NOT = SPACES
        MOVE 1 TO BRUTE-MODE
    END-IF.
    MOVE SPACES TO ENV-VALUE.
    ACCEPT ENV-VALUE FROM ENVIRONMENT "MB_PREVIEW"
        ON EXCEPTION MOVE SPACES TO ENV-VALUE
    END-ACCEPT.
    IF ENV-VALUE NOT = SPACES
        PERFORM VARYING PREVIEW-LEVEL FROM 1 BY 1
                UNTIL PREVIEW-LEVEL > 8
                OR PREVIEW-SCALE-OF(PREVIEW-LEVEL)
                   = FUNCTION NUMVAL(ENV-VALUE)
            CONTINUE
        END-PERFORM
        IF PREVIEW-LEVEL <= 8
            MOVE PREVIEW-SCALE-OF(PREVIEW-LEVEL) TO PREVIEW-SCALE
            MOVE 1 TO PREVIEW-PINNED
        ELSE
            MOVE 3 TO PREVIEW-LEVEL
        END-IF
    END-IF.
    MOVE SPACES TO ENV-VALUE.
    ACCEPT ENV-VALUE FROM ENVIRONMENT "MB_NOPERTURB"
        ON EXCEPTION MOVE SPACES TO ENV-VALUE
    END-ACCEPT.
    IF ENV-VALUE NOT = SPACES
        MOVE 1 TO NO-PERTURB-MODE
    END-IF.

    MOVE SPACES TO ENV-VALUE.
    ACCEPT ENV-VALUE FROM ENVIRONMENT "MB_CENTER_X"
        ON EXCEPTION MOVE SPACES TO ENV-VALUE
    END-ACCEPT.
    IF ENV-VALUE NOT = SPACES
        MOVE ENV-VALUE TO LOC-IN
        PERFORM PARSE-LOCATION
        IF LOC-OK = 1
            MOVE HP-TEMP TO HP-CENTER-X
        END-IF
    END-IF.
    MOVE SPACES TO ENV-VALUE.
    ACCEPT ENV-VALUE FROM ENVIRONMENT "MB_CENTER_Y"
        ON EXCEPTION MOVE SPACES TO ENV-VALUE
    END-ACCEPT.
    IF ENV-VALUE NOT = SPACES
        MOVE ENV-VALUE TO LOC-IN
        PERFORM PARSE-LOCATION
        IF LOC-OK = 1
            MOVE HP-TEMP TO HP-CENTER-Y
        END-IF
    END-IF.
    MOVE SPACES TO ENV-VALUE.
    ACCEPT ENV-VALUE FROM ENVIRONMENT "MB_HALF_WIDTH"
        ON EXCEPTION MOVE SPACES TO ENV-VALUE
    END-ACCEPT.
    IF ENV-VALUE NOT = SPACES
        MOVE ENV-VALUE TO LOC-IN
        PERFORM PARSE-LOCATION
        IF LOC-OK = 1 AND HP-TEMP > 0
            MOVE HP-TEMP TO HP-HALF-WIDTH
        END-IF
    END-IF.
    PERFORM CLAMP-VIEWPORT.

*> Parse "-0.7436", "1.5e-20", ".131" etc. from LOC-IN into
*> HP-TEMP. Plain decimal digits go straight into the field's
*> byte layout; an exponent is applied by exact repeated
*> multiplication / division by 10.
PARSE-LOCATION.
    MOVE 0 TO LOC-OK.
    MOVE FUNCTION UPPER-CASE(FUNCTION TRIM(LOC-IN)) TO LOC-IN.
    MOVE SPACES TO LOC-MANT LOC-EXP.
    IF LOC-IN = SPACES
        EXIT PARAGRAPH
    END-IF.
    UNSTRING LOC-IN DELIMITED BY "E" INTO LOC-MANT LOC-EXP.
    MOVE "+" TO LOC-SIGN.
    IF LOC-MANT(1:1) = "-"
        MOVE "-" TO LOC-SIGN
        MOVE LOC-MANT(2:) TO LOC-MANT
    ELSE
        IF LOC-MANT(1:1) = "+"
            MOVE LOC-MANT(2:) TO LOC-MANT
        END-IF
    END-IF.
    MOVE SPACES TO LOC-INT LOC-FRAC.
    UNSTRING LOC-MANT DELIMITED BY "." INTO LOC-INT LOC-FRAC.
    IF LOC-INT = SPACES
        MOVE "0" TO LOC-INT
    END-IF.
    INSPECT LOC-FRAC REPLACING ALL SPACE BY "0".
    IF FUNCTION TEST-NUMVAL(LOC-INT) NOT = 0
        EXIT PARAGRAPH
    END-IF.
    IF FUNCTION NUMVAL(LOC-INT) > 99
        EXIT PARAGRAPH
    END-IF.
    MOVE FUNCTION NUMVAL(LOC-INT) TO LOC-INT-NUM.
    MOVE LOC-SIGN TO HP-TEMP-B(1:1).
    MOVE LOC-INT-NUM TO HP-TEMP-B(2:2).
    MOVE LOC-FRAC TO HP-TEMP-B(4:36).
    IF LOC-EXP NOT = SPACES
        IF FUNCTION TEST-NUMVAL(LOC-EXP) NOT = 0
            EXIT PARAGRAPH
        END-IF
        MOVE FUNCTION NUMVAL(LOC-EXP) TO LOC-EXP-NUM
        IF LOC-EXP-NUM > 40 OR LOC-EXP-NUM < -40
            EXIT PARAGRAPH
        END-IF
        IF LOC-EXP-NUM > 0
            PERFORM LOC-EXP-NUM TIMES
                MULTIPLY 10 BY HP-TEMP
            END-PERFORM
        END-IF
        IF LOC-EXP-NUM < 0
            COMPUTE LOC-I = - LOC-EXP-NUM
            PERFORM LOC-I TIMES
                DIVIDE 10 INTO HP-TEMP
            END-PERFORM
        END-IF
    END-IF.
    MOVE 1 TO LOC-OK.

SHOW-LOCATION.
    DISPLAY "Location: MB_CENTER_X="
        HP-CENTER-X-B(1:1) HP-CENTER-X-B(2:2) "."
        HP-CENTER-X-B(4:36)
        " MB_CENTER_Y="
        HP-CENTER-Y-B(1:1) HP-CENTER-Y-B(2:2) "."
        HP-CENTER-Y-B(4:36)
        " MB_HALF_WIDTH="
        HP-HALF-WIDTH-B(2:2) "." HP-HALF-WIDTH-B(4:36).

*> ------------------------------------------------------------
*> Poll calibration.
*>
*> The only way to look for a key without blocking in standard
*> GnuCOBOL is ACCEPT ... WITH TIME-OUT AFTER n, and the unit of
*> n is normally a second. COB_TIMEOUT_SCALE=2 makes it 10 ms,
*> but some builds only read that variable at start-up, before
*> SET ENVIRONMENT can set it. So at start-up the program times
*> CALIB-REPS polls at TIME-OUT AFTER 1: if a poll is cheap, the
*> preview loop polls POLLS-PER-FRAME times per frame (spread over
*> the pixels it computes) and abandons the frame when a key
*> arrives; if a poll costs a second, polling is switched off and
*> the user is told to export the variable in the shell.
*> ------------------------------------------------------------
CALIBRATE-POLL.
    MOVE SPACES TO ENV-VALUE.
    ACCEPT ENV-VALUE FROM ENVIRONMENT "MB_POLL"
        ON EXCEPTION MOVE SPACES TO ENV-VALUE
    END-ACCEPT.

    EVALUATE FUNCTION LOWER-CASE(FUNCTION TRIM(ENV-VALUE))
        WHEN "off"
            MOVE 0 TO POLL-ENABLED
            DISPLAY "Mid-render polling disabled by MB_POLL=off."
            EXIT PARAGRAPH
        WHEN "on"
            MOVE 1 TO POLL-ENABLED
            DISPLAY "Mid-render polling forced on by MB_POLL=on "
                "(not calibrated)."
            EXIT PARAGRAPH
        WHEN OTHER
            CONTINUE
    END-EVALUATE.

    DISPLAY " ".
    DISPLAY "Calibrating keyboard poll - do not press any keys...".

    MOVE 0 TO CALIB-DIRTY.
    MOVE 1 TO TIMEOUT-TICKS.
    PERFORM POLL-KEY.
    PERFORM MEASURE-POLL-COST.
    MOVE MEASURED-TOTAL-CS TO TICK-TOTAL-CS.
    COMPUTE TICK-COST-CS = TICK-TOTAL-CS / CALIB-REPS.

    MOVE TICK-TOTAL-CS TO NUM-OUT.
    MOVE CALIB-REPS TO NUM-OUT2.
    DISPLAY "  " FUNCTION TRIM(NUM-OUT) " cs for "
        FUNCTION TRIM(NUM-OUT2) " polls at TIME-OUT AFTER 1".

    IF TICK-COST-CS > MAX-POLL-COST-CS
        MOVE 0 TO POLL-ENABLED
        DISPLAY "  One tick costs far too much, so COB_TIMEOUT_SCALE"
        DISPLAY "  did not take effect on this build. Export it in"
        DISPLAY "  the shell before launching, then rerun:"
        DISPLAY "    export COB_TIMEOUT_SCALE=2"
        DISPLAY "  Mid-render interrupt OFF for this run; preview"
        DISPLAY "  frames will finish before each key is read."
        DISPLAY " "
        EXIT PARAGRAPH
    END-IF.

    IF TICK-TOTAL-CS <= 0
        MOVE 4 TO TIMEOUT-TICKS
    ELSE
        COMPUTE TIMEOUT-TICKS =
            (TARGET-POLL-CS * CALIB-REPS) / TICK-TOTAL-CS
    END-IF.
    IF TIMEOUT-TICKS < 1
        MOVE 1 TO TIMEOUT-TICKS
    END-IF.
    IF TIMEOUT-TICKS > MAX-TIMEOUT-TICKS
        MOVE MAX-TIMEOUT-TICKS TO TIMEOUT-TICKS
    END-IF.

    COMPUTE POLL-COST-CS =
        (TICK-TOTAL-CS * TIMEOUT-TICKS) / CALIB-REPS.
    IF POLL-COST-CS < 1
        MOVE 1 TO POLL-COST-CS
    END-IF.

    COMPUTE POLLS-PER-FRAME = FRAME-POLL-BUDGET-CS / POLL-COST-CS.
    IF POLLS-PER-FRAME < 1
        MOVE 1 TO POLLS-PER-FRAME
    END-IF.
    IF POLLS-PER-FRAME > MAX-POLLS-PER-FRAME
        MOVE MAX-POLLS-PER-FRAME TO POLLS-PER-FRAME
    END-IF.
    MOVE 1 TO POLL-ENABLED.

    MOVE TIMEOUT-TICKS TO NUM-OUT.
    MOVE POLLS-PER-FRAME TO NUM-OUT2.
    DISPLAY "  mid-render interrupt ON at TIME-OUT AFTER "
        FUNCTION TRIM(NUM-OUT) ", " FUNCTION TRIM(NUM-OUT2)
        " polls per frame.".

    IF CALIB-DIRTY = 1
        DISPLAY "  (a key was pressed during calibration - the"
        DISPLAY "   numbers above may be low; rerun to redo it.)"
    END-IF.
    DISPLAY " ".

MEASURE-POLL-COST.
    PERFORM GET-NOW.
    MOVE NOW-TOTAL-CS TO T-START.
    PERFORM VARYING CALIB-I FROM 1 BY 1
            UNTIL CALIB-I > CALIB-REPS
        PERFORM POLL-KEY
        PERFORM CLASSIFY-KEY
        IF REAL-KEY
            MOVE 1 TO CALIB-DIRTY
        END-IF
    END-PERFORM.
    PERFORM GET-NOW.
    COMPUTE MEASURED-TOTAL-CS = NOW-TOTAL-CS - T-START.
    IF MEASURED-TOTAL-CS < 0
        ADD 8640000 TO MEASURED-TOTAL-CS
    END-IF.

GET-NOW.
    MOVE FUNCTION CURRENT-DATE TO NOW-STAMP.
    COMPUTE NOW-TOTAL-CS =
        (((NOW-HH * 60) + NOW-MI) * 60 + NOW-SS) * 100 + NOW-CS.

*> ------------------------------------------------------------
*> Viewport
*> ------------------------------------------------------------
COMPUTE-VIEWPORT.
    COMPUTE HP-HALF-HEIGHT =
        HP-HALF-WIDTH * SCREEN-HEIGHT / SCREEN-WIDTH.
    COMPUTE HP-REAL-MIN = HP-CENTER-X - HP-HALF-WIDTH.
    COMPUTE HP-IMAG-MIN = HP-CENTER-Y - HP-HALF-HEIGHT.
    COMPUTE HP-PAN-STEP-X = HP-HALF-WIDTH * 0.15.
    COMPUTE HP-PAN-STEP-Y = HP-HALF-HEIGHT * 0.15.
    IF HP-HALF-WIDTH < PERTURB-BELOW AND NO-PERTURB-MODE = 0
        MOVE 1 TO PERTURB-FLAG
    ELSE
        MOVE 0 TO PERTURB-FLAG
    END-IF.
    PERFORM ADAPT-MAX-ITER.

ADAPT-MAX-ITER.
    *> Iteration cap grows with the number of zoom doublings L
    *> (60 + 40 L + 0.4 L^2: ~1000 at 1e-6, ~2300 at 1e-12, ~8000
    *> at 1e-30), then is scaled by the user's [ ] setting.
    COMPUTE ZOOM-LOG2 =
        FUNCTION LOG(BASE-HALF-WIDTH / HP-HALF-WIDTH) / 0.693147.
    IF ZOOM-LOG2 < 0
        MOVE 0 TO ZOOM-LOG2
    END-IF.
    COMPUTE ITER-CALC = (60 + 40 * ZOOM-LOG2 + 0.4 * ZOOM-LOG2 ** 2)
        * ITER-MULT-NUM / ITER-MULT-DEN.
    COMPUTE FULL-MAX-ITER = ITER-CALC.
    IF FULL-MAX-ITER < 16
        MOVE 16 TO FULL-MAX-ITER
    END-IF.
    IF FULL-MAX-ITER > MAX-ITER-CAP
        MOVE MAX-ITER-CAP TO FULL-MAX-ITER
    END-IF.
    COMPUTE PREVIEW-MAX-ITER = FULL-MAX-ITER / 2.
    IF PREVIEW-MAX-ITER < 25
        MOVE 25 TO PREVIEW-MAX-ITER
    END-IF.
    IF PREVIEW-MAX-ITER > FULL-MAX-ITER
        MOVE FULL-MAX-ITER TO PREVIEW-MAX-ITER
    END-IF.

*> ------------------------------------------------------------
*> Frame rendering
*> ------------------------------------------------------------
RENDER-FRAME.
    PERFORM GET-NOW.
    MOVE NOW-TOTAL-CS TO FRAME-START-CS.

    *> rounded up: a partial last row/column of blocks is
    *> rendered and clipped at the screen edge by BLIT-FRAME
    COMPUTE RENDER-WIDTH =
        (SCREEN-WIDTH + RENDER-SCALE - 1) / RENDER-SCALE.
    COMPUTE RENDER-HEIGHT =
        (SCREEN-HEIGHT + RENDER-SCALE - 1) / RENDER-SCALE.
    COMPUTE HP-REAL-STEP = HP-HALF-WIDTH * 2 / RENDER-WIDTH.
    COMPUTE HP-IMAG-STEP = HP-HALF-HEIGHT * 2 / RENDER-HEIGHT.

    IF RENDER-SCALE = 1
        MOVE FULL-MAX-ITER TO CURRENT-MAX-ITER
    ELSE
        MOVE PREVIEW-MAX-ITER TO CURRENT-MAX-ITER
    END-IF.
    SET MAX-ITER-IDX TO CURRENT-MAX-ITER.

    IF HP-CENTER-Y = ZERO AND FUNCTION MOD(RENDER-HEIGHT, 2) = 0
        MOVE 1 TO SYMMETRIC-FLAG
        COMPUTE REGION-HEIGHT = RENDER-HEIGHT / 2
    ELSE
        MOVE 0 TO SYMMETRIC-FLAG
        MOVE RENDER-HEIGHT TO REGION-HEIGHT
    END-IF.

    PERFORM BUILD-TABLES.
    IF PERTURB
        PERFORM CHOOSE-REFERENCE
        PERFORM COMPUTE-REF-ORBIT
        PERFORM BUILD-DELTA-TABLES
    END-IF.
    PERFORM BUILD-ITER-PALETTE.

    COMPUTE P-LEN = RENDER-WIDTH * RENDER-HEIGHT * 4.
    MOVE ALL X"FFFFFFFF" TO ITER-BUF-B(1:P-LEN).
    MOVE 0 TO PIXELS-COMPUTED.
    MOVE 0 TO PIXELS-FILLED.
    MOVE 0 TO RECTS-DONE.
    MOVE 0 TO REBASES.
    MOVE 0 TO DELTA-EXITS.
    MOVE 0 TO BREAK-RENDER.
    MOVE 0 TO GOT-INPUT-FLAG.
    MOVE 0 TO PIXELS-SINCE-POLL.

    *> Polling: preview frames get the calibrated poll budget;
    *> the full-res render polls sparsely so it can be aborted.
    IF POLL-ENABLED = 1
        MOVE 1 TO POLL-ACTIVE
        COMPUTE POLL-EVERY-PIXELS =
            (RENDER-WIDTH * REGION-HEIGHT) / (3 * POLLS-PER-FRAME)
        IF POLL-EVERY-PIXELS < 200
            MOVE 200 TO POLL-EVERY-PIXELS
        END-IF
    ELSE
        MOVE 0 TO POLL-ACTIVE
    END-IF.

    MOVE 1 TO RECT-TOP.
    MOVE 1 TO RS-X0(1).
    MOVE 1 TO RS-Y0(1).
    MOVE RENDER-WIDTH TO RS-X1(1).
    MOVE REGION-HEIGHT TO RS-Y1(1).

    PERFORM UNTIL RECT-TOP < 1 OR BREAK-RENDER = 1
        MOVE RECT(RECT-TOP) TO CUR-RECT
        SUBTRACT 1 FROM RECT-TOP
        PERFORM PROCESS-RECT
        ADD 1 TO RECTS-DONE
    END-PERFORM.

    IF BREAK-RENDER = 0
        IF VIEW-SYMMETRIC
            PERFORM MIRROR-ROWS
        END-IF
        PERFORM BLIT-FRAME
        IF DUMP-ENABLED = 1
            PERFORM DUMP-ITERATIONS
        END-IF
        IF HP-HALF-WIDTH < BEST-SCAN-BELOW
            PERFORM FIND-BEST-PIXEL
        END-IF
    END-IF.
    PERFORM GET-NOW.
    COMPUTE FRAME-MS = (NOW-TOTAL-CS - FRAME-START-CS) * 10.
    IF FRAME-MS < 0
        ADD 86400000 TO FRAME-MS
    END-IF.

BUILD-TABLES.
    PERFORM VARYING PX FROM 1 BY 1 UNTIL PX > RENDER-WIDTH
        COMPUTE CX-TAB(PX) =
            HP-REAL-MIN + (PX - 0.5) * HP-REAL-STEP
    END-PERFORM.
    MOVE 0 TO P-IDX.
    PERFORM VARYING PY FROM 1 BY 1 UNTIL PY > RENDER-HEIGHT
        COMPUTE CY-TAB(PY) =
            HP-IMAG-MIN + (PY - 0.5) * HP-IMAG-STEP
        MOVE P-IDX TO ROW-BASE-TAB(PY)
        ADD RENDER-WIDTH TO P-IDX
    END-PERFORM.

BUILD-ITER-PALETTE.
    MOVE UNSET-PIXEL TO PAL-BY-ITER(1).
    MOVE 1 TO PAL-J.
    PERFORM VARYING PAL-I FROM 2 BY 1
            UNTIL PAL-I > CURRENT-MAX-ITER + 1
        MOVE PAL-CYCLE(PAL-J) TO PAL-BY-ITER(PAL-I)
        ADD 1 TO PAL-J
        IF PAL-J > PAL-CYCLE-LEN
            MOVE 1 TO PAL-J
        END-IF
    END-PERFORM.
    MOVE BLACK-PIXEL TO PAL-BY-ITER(CURRENT-MAX-ITER + 2).

*> ------------------------------------------------------------
*> Perturbation: reference orbit and per-frame delta tables
*> ------------------------------------------------------------
CHOOSE-REFERENCE.
    *> Last frame's deepest pixel if it's still near the view,
    *> otherwise the centre.
    MOVE 0 TO USE-BEST-FLAG.
    IF BEST-VALID = 1
        COMPUTE HP-TEMP = HP-HALF-WIDTH * 1.5
        IF FUNCTION ABS(HP-BEST-X - HP-CENTER-X) <= HP-TEMP
           AND FUNCTION ABS(HP-BEST-Y - HP-CENTER-Y) <= HP-TEMP
            MOVE 1 TO USE-BEST-FLAG
        END-IF
    END-IF.
    IF USE-BEST-FLAG = 1
        MOVE HP-BEST-X TO HP-REF-X
        MOVE HP-BEST-Y TO HP-REF-Y
    ELSE
        MOVE HP-CENTER-X TO HP-REF-X
        MOVE HP-CENTER-Y TO HP-REF-Y
    END-IF.

COMPUTE-REF-ORBIT.
    *> Reuse the cached orbit if it's for the same point and is
    *> long enough (or ended by escaping).
    IF ORBIT-VALID = 1
       AND HP-ORBIT-X = HP-REF-X AND HP-ORBIT-Y = HP-REF-Y
       AND (ORBIT-ESCAPED = 1 OR ORBIT-LEN >= FULL-MAX-ITER)
        EXIT PARAGRAPH
    END-IF.
    MOVE HP-REF-X TO HP-ORBIT-X.
    MOVE HP-REF-Y TO HP-ORBIT-Y.
    MOVE 0 TO ORBIT-ESCAPED.
    MOVE ZERO TO HZX HZY HZX2 HZY2.
    *> Z_0 = 0 at index 1
    MOVE 0 TO ORBIT-I.
    PERFORM STORE-ORBIT-POINT.
    PERFORM VARYING ORBIT-I FROM 1 BY 1
            UNTIL ORBIT-I > FULL-MAX-ITER OR ORBIT-ESCAPED = 1
        COMPUTE HZY = 2 * HZX * HZY + HP-REF-Y
        COMPUTE HZX = HZX2 - HZY2 + HP-REF-X
        COMPUTE HZX2 = HZX * HZX
        COMPUTE HZY2 = HZY * HZY
        PERFORM STORE-ORBIT-POINT
        IF HZX2 + HZY2 > 4
            MOVE 1 TO ORBIT-ESCAPED
        END-IF
    END-PERFORM.
    *> ORBIT-LEN = last stored n; entries run 1 .. ORBIT-LEN + 1
    IF ORBIT-ESCAPED = 1
        MOVE ORBIT-I TO ORBIT-LEN
    ELSE
        MOVE FULL-MAX-ITER TO ORBIT-LEN
    END-IF.
    MOVE 1 TO ORBIT-VALID.

STORE-ORBIT-POINT.
    MOVE HZX TO HP-ZXR(ORBIT-I + 1).
    MOVE HZY TO HP-ZYR(ORBIT-I + 1).
    MOVE HZX TO ZXR(ORBIT-I + 1).
    MOVE HZY TO ZYR(ORBIT-I + 1).
    COMPUTE ZMAGR(ORBIT-I + 1) =
        ZXR(ORBIT-I + 1) * ZXR(ORBIT-I + 1)
        + ZYR(ORBIT-I + 1) * ZYR(ORBIT-I + 1).

BUILD-DELTA-TABLES.
    *> Where the delta loop stops: the index of the first orbit
    *> point outside the escape circle, or past the end.
    *> (one before the escaping point, see DELTA-EXIT)
    IF ORBIT-ESCAPED = 1
        MOVE ORBIT-LEN TO REF-ESC-IDX
    ELSE
        COMPUTE REF-ESC-IDX = ORBIT-LEN + 2
    END-IF.
    *> Starting stage k0: the largest pixel offset in the frame
    *> (~2.5 half-widths, or a bit more with an off-centre
    *> reference) lands around D = 100.
    COMPUTE K-LOG = FUNCTION LOG10(40 / HP-HALF-WIDTH).
    COMPUTE K0 = K-LOG.
    IF K0 > K-LOG
        SUBTRACT 1 FROM K0
    END-IF.
    IF K0 < K-EXIT + 1
        COMPUTE K0 = K-EXIT + 1
    END-IF.
    IF K0 > MAX-K
        MOVE MAX-K TO K0
    END-IF.
    PERFORM VARYING PX FROM 1 BY 1 UNTIL PX > RENDER-WIDTH
        COMPUTE D0X-TAB(PX) =
            (HP-REAL-MIN + (PX - 0.5) * HP-REAL-STEP - HP-REF-X)
            * TENK-TAB(K0 + 1)
    END-PERFORM.
    PERFORM VARYING PY FROM 1 BY 1 UNTIL PY > RENDER-HEIGHT
        COMPUTE D0Y-TAB(PY) =
            (HP-IMAG-MIN + (PY - 0.5) * HP-IMAG-STEP - HP-REF-Y)
            * TENK-TAB(K0 + 1)
    END-PERFORM.

BUILD-STAGE-TABLES.
    *> TA(k) * TB(k) = 10^-k, TENK(k) = 10^k, ZLIM(k) = 80000 * 10^-2k
    MOVE 1 TO TA-TAB(1) TB-TAB(1) TENK-TAB(1).
    PERFORM VARYING K-CUR FROM 1 BY 1 UNTIL K-CUR > MAX-K
        COMPUTE TENK-TAB(K-CUR + 1) = TENK-TAB(K-CUR) * 10
        IF K-CUR <= 18
            COMPUTE TA-TAB(K-CUR + 1) = TA-TAB(K-CUR) / 10
            MOVE 1 TO TB-TAB(K-CUR + 1)
        ELSE
            MOVE TA-TAB(K-CUR) TO TA-TAB(K-CUR + 1)
            COMPUTE TB-TAB(K-CUR + 1) = TB-TAB(K-CUR) / 10
        END-IF
    END-PERFORM.
    *> ZLIM(k) is compared against |Z_n|^2 stored at 16 decimals.
    *> For k <= 10 it is the real bound (2 * sqrt(2) * 100 *
    *> 10^-k)^2. For k >= 11 that bound is below 1e-16, the
    *> resolution of ZMAGR, so the entry is 0: the prefilter then
    *> passes any Z with |Z| < 1e-8, a superset of what the exact
    *> test in DELTA-REBASE needs (no rebase can be missed, only a
    *> few extra exact tests are run).
    PERFORM VARYING K-CUR FROM 0 BY 1 UNTIL K-CUR > MAX-K
        EVALUATE TRUE
            WHEN K-CUR < 2
                *> 80000 * 10^-2k doesn't fit the field; never
                *> used (k never drops below K-EXIT)
                MOVE 900 TO ZLIM-TAB(K-CUR + 1)
            WHEN K-CUR > 10
                MOVE FZERO TO ZLIM-TAB(K-CUR + 1)
            WHEN OTHER
                COMPUTE ZLIM-TAB(K-CUR + 1) = 80000
                    * TA-TAB(K-CUR + 1) * TB-TAB(K-CUR + 1)
                    * TA-TAB(K-CUR + 1) * TB-TAB(K-CUR + 1)
        END-EVALUATE
    END-PERFORM.

FIND-BEST-PIXEL.
    *> Highest iteration count in the frame just rendered (only
    *> the computed region: the mirrored half is a copy anyway).
    MOVE -1 TO BEST-ITER.
    MOVE 1 TO BEST-IDX.
    COMPUTE P-LEN = RENDER-WIDTH * REGION-HEIGHT.
    PERFORM VARYING P-IDX FROM 1 BY 1 UNTIL P-IDX > P-LEN
        IF ITER-CELL(P-IDX) > BEST-ITER
            MOVE ITER-CELL(P-IDX) TO BEST-ITER
            MOVE P-IDX TO BEST-IDX
        END-IF
    END-PERFORM.
    COMPUTE BEST-PY = (BEST-IDX - 1) / RENDER-WIDTH.
    COMPUTE BEST-PX = BEST-IDX - BEST-PY * RENDER-WIDTH.
    ADD 1 TO BEST-PY.
    COMPUTE HP-BEST-X = HP-REAL-MIN + (BEST-PX - 0.5) * HP-REAL-STEP.
    COMPUTE HP-BEST-Y = HP-IMAG-MIN + (BEST-PY - 0.5) * HP-IMAG-STEP.
    MOVE 1 TO BEST-VALID.

*> ------------------------------------------------------------
*> Mariani-Silver subdivision (see header, item 1)
*> ------------------------------------------------------------
PROCESS-RECT.
    COMPUTE CR-W = CR-X1 - CR-X0 + 1.
    COMPUTE CR-H = CR-Y1 - CR-Y0 + 1.

    PERFORM COMPUTE-BORDER.
    IF BREAK-RENDER = 1
        EXIT PARAGRAPH
    END-IF.

    IF BRUTE-FORCE
        PERFORM COMPUTE-INTERIOR
        EXIT PARAGRAPH
    END-IF.

    IF BORDER-UNIFORM
        IF CR-W > 2 AND CR-H > 2
            PERFORM FILL-INTERIOR
        END-IF
        EXIT PARAGRAPH
    END-IF.

    IF CR-W <= MIN-SPLIT OR CR-H <= MIN-SPLIT
        IF CR-W > 2 AND CR-H > 2
            PERFORM COMPUTE-INTERIOR
        END-IF
        EXIT PARAGRAPH
    END-IF.

    IF RECT-TOP + 2 > RECT-STACK-SIZE
        PERFORM COMPUTE-INTERIOR
        EXIT PARAGRAPH
    END-IF.
    IF CR-W >= CR-H
        COMPUTE CR-MID = (CR-X0 + CR-X1) / 2
        ADD 1 TO RECT-TOP
        MOVE CR-X0 TO RS-X0(RECT-TOP)
        MOVE CR-Y0 TO RS-Y0(RECT-TOP)
        MOVE CR-MID TO RS-X1(RECT-TOP)
        MOVE CR-Y1 TO RS-Y1(RECT-TOP)
        ADD 1 TO RECT-TOP
        MOVE CR-MID TO RS-X0(RECT-TOP)
        MOVE CR-Y0 TO RS-Y0(RECT-TOP)
        MOVE CR-X1 TO RS-X1(RECT-TOP)
        MOVE CR-Y1 TO RS-Y1(RECT-TOP)
    ELSE
        COMPUTE CR-MID = (CR-Y0 + CR-Y1) / 2
        ADD 1 TO RECT-TOP
        MOVE CR-X0 TO RS-X0(RECT-TOP)
        MOVE CR-Y0 TO RS-Y0(RECT-TOP)
        MOVE CR-X1 TO RS-X1(RECT-TOP)
        MOVE CR-MID TO RS-Y1(RECT-TOP)
        ADD 1 TO RECT-TOP
        MOVE CR-X0 TO RS-X0(RECT-TOP)
        MOVE CR-MID TO RS-Y0(RECT-TOP)
        MOVE CR-X1 TO RS-X1(RECT-TOP)
        MOVE CR-Y1 TO RS-Y1(RECT-TOP)
    END-IF.

COMPUTE-BORDER.
    MOVE 1 TO BORDER-SAME-FLAG.
    MOVE CR-X0 TO PX.
    MOVE CR-Y0 TO PY.
    PERFORM ENSURE-PIXEL.
    MOVE ITER-CELL(P-IDX) TO BORDER-VALUE.

    PERFORM VARYING PX FROM CR-X0 BY 1
            UNTIL PX > CR-X1 OR BREAK-RENDER = 1
        MOVE CR-Y0 TO PY
        PERFORM ENSURE-PIXEL
        IF ITER-CELL(P-IDX) NOT = BORDER-VALUE
            MOVE 0 TO BORDER-SAME-FLAG
        END-IF
        MOVE CR-Y1 TO PY
        PERFORM ENSURE-PIXEL
        IF ITER-CELL(P-IDX) NOT = BORDER-VALUE
            MOVE 0 TO BORDER-SAME-FLAG
        END-IF
    END-PERFORM.

    PERFORM VARYING PY FROM CR-Y0 BY 1
            UNTIL PY > CR-Y1 OR BREAK-RENDER = 1
        MOVE CR-X0 TO PX
        PERFORM ENSURE-PIXEL
        IF ITER-CELL(P-IDX) NOT = BORDER-VALUE
            MOVE 0 TO BORDER-SAME-FLAG
        END-IF
        MOVE CR-X1 TO PX
        PERFORM ENSURE-PIXEL
        IF ITER-CELL(P-IDX) NOT = BORDER-VALUE
            MOVE 0 TO BORDER-SAME-FLAG
        END-IF
    END-PERFORM.

COMPUTE-INTERIOR.
    PERFORM VARYING PY FROM CR-Y0 BY 1
            UNTIL PY >= CR-Y1 OR BREAK-RENDER = 1
        IF PY > CR-Y0
            PERFORM VARYING PX FROM CR-X0 BY 1
                    UNTIL PX >= CR-X1
                IF PX > CR-X0
                    PERFORM ENSURE-PIXEL
                END-IF
            END-PERFORM
        END-IF
    END-PERFORM.

FILL-INTERIOR.
    COMPUTE P-LEN = CR-W - 2.
    COMPUTE FILL-ROW-BYTES = P-LEN * 4.
    COMPUTE FILL-ROW-START = ROW-BASE-TAB(CR-Y0 + 1) + CR-X0 + 1.
    MOVE FILL-ROW-START TO P-IDX.
    PERFORM P-LEN TIMES
        MOVE BORDER-VALUE TO ITER-CELL(P-IDX)
        ADD 1 TO P-IDX
    END-PERFORM.
    COMPUTE P-OFF = (FILL-ROW-START - 1) * 4 + 1.
    MOVE P-OFF TO P-OFF2.
    MOVE CR-Y0 TO PY.
    ADD 2 TO PY.
    PERFORM UNTIL PY >= CR-Y1
        ADD RENDER-WIDTH TO P-OFF2
        ADD RENDER-WIDTH TO P-OFF2
        ADD RENDER-WIDTH TO P-OFF2
        ADD RENDER-WIDTH TO P-OFF2
        MOVE ITER-BUF-B(P-OFF:FILL-ROW-BYTES)
          TO ITER-BUF-B(P-OFF2:FILL-ROW-BYTES)
        ADD 1 TO PY
    END-PERFORM.
    COMPUTE PIXELS-FILLED = PIXELS-FILLED + P-LEN * (CR-H - 2).

ENSURE-PIXEL.
    MOVE ROW-BASE-TAB(PY) TO P-IDX.
    ADD PX TO P-IDX.
    IF ITER-CELL(P-IDX) = ITER-UNSET
        MOVE CX-TAB(PX) TO FCX
        MOVE CY-TAB(PY) TO FCY
        IF PERTURB
            PERFORM ITERATE-POINT-PERTURB
        ELSE
            PERFORM ITERATE-POINT
        END-IF
        MOVE ITER-RESULT TO ITER-CELL(P-IDX)
        ADD 1 TO PIXELS-COMPUTED
        IF POLL-ACTIVE = 1
            ADD 1 TO PIXELS-SINCE-POLL
            IF PIXELS-SINCE-POLL >= POLL-EVERY-PIXELS
                PERFORM MIDFRAME-POLL
            END-IF
        END-IF
    END-IF.

MIDFRAME-POLL.
    MOVE 0 TO PIXELS-SINCE-POLL.
    PERFORM POLL-KEY.
    PERFORM CLASSIFY-KEY.
    IF REAL-KEY
        MOVE 1 TO BREAK-RENDER
        MOVE 1 TO GOT-INPUT-FLAG
    END-IF.

*> ------------------------------------------------------------
*> Direct iteration: z = z^2 + c for c = (FCX, FCY)
*> ------------------------------------------------------------
ITERATE-POINT.
    PERFORM CARDIOID-CHECK.
    IF INSIDE-CARDIOID-OR-BULB
        MOVE CURRENT-MAX-ITER TO ITER-RESULT
        EXIT PARAGRAPH
    END-IF.
    MOVE FZERO TO FZX.
    MOVE FZERO TO FZY.
    MOVE FZERO TO FZX2.
    MOVE FZERO TO FZY2.
    MOVE Z-PAIR TO Z-CHECK-PAIR.
    SET ITER TO 0.
    SET NEXT-CHECK TO 8.
    PERFORM STANDARD-LOOP.

CARDIOID-CHECK.
    *> INSIDE-FLAG = 1 if c is inside the main cardioid or the
    *> period-2 bulb (16-decimal test, fine at any zoom: a point
    *> misclassified by 1e-16 would need ~1e8 iterations anyway).
    MOVE 0 TO INSIDE-FLAG.
    COMPUTE FQ-TERM = FCX - 0.25.
    COMPUTE FQ = FQ-TERM * FQ-TERM + FCY * FCY.
    COMPUTE FTEST = FQ * (FQ + FQ-TERM) - 0.25 * FCY * FCY.
    IF RTEST <= 0
        MOVE 1 TO INSIDE-FLAG
        EXIT PARAGRAPH
    END-IF.
    COMPUTE FTEST = (FCX + 1) * (FCX + 1) + FCY * FCY - 0.0625.
    IF RTEST <= 0
        MOVE 1 TO INSIDE-FLAG
    END-IF.

STANDARD-LOOP.
    *> Runs from the current FZX/FZY/FZX2/FZY2/ITER state.
    PERFORM UNTIL ITER >= MAX-ITER-IDX OR RZX2 + RZY2 > RFOUR
        COMPUTE FZY = 2 * FZX * FZY + FCY
        COMPUTE FZX = FZX2 - FZY2 + FCX
        COMPUTE FZX2 = FZX * FZX
        COMPUTE FZY2 = FZY * FZY
        SET ITER UP BY 1
        IF Z-PAIR = Z-CHECK-PAIR
            SET ITER TO MAX-ITER-IDX
        ELSE
            IF ITER = NEXT-CHECK
                MOVE Z-PAIR TO Z-CHECK-PAIR
                SET NEXT-CHECK UP BY NEXT-CHECK
            END-IF
        END-IF
    END-PERFORM.
    SET ITER-RESULT TO ITER.

*> ------------------------------------------------------------
*> Perturbed iteration: D = delta * 10^k,
*>   D' = 2 Z D + D^2 * 10^-k + D0
*> ------------------------------------------------------------
ITERATE-POINT-PERTURB.
    PERFORM CARDIOID-CHECK.
    IF INSIDE-CARDIOID-OR-BULB
        MOVE CURRENT-MAX-ITER TO ITER-RESULT
        EXIT PARAGRAPH
    END-IF.
    MOVE FZERO TO DX.
    MOVE FZERO TO DY.
    MOVE D0X-TAB(PX) TO D0X.
    MOVE D0Y-TAB(PY) TO D0Y.
    MOVE K0 TO K-CUR.
    MOVE TA-TAB(K0 + 1) TO TA.
    MOVE TB-TAB(K0 + 1) TO TB.
    MOVE ZLIM-TAB(K0 + 1) TO ZLIM.
    SET ITER TO 0.
    MOVE 1 TO REF-IDX.
    MOVE 0 TO DELTA-DONE.

    PERFORM UNTIL ITER >= MAX-ITER-IDX
            OR REF-IDX >= REF-ESC-IDX OR DELTA-DONE = 1
        COMPUTE DXN = 2 * (ZXR(REF-IDX) * DX - ZYR(REF-IDX) * DY)
            + (DX * DX - DY * DY) * TA * TB + D0X
        COMPUTE DY = 2 * (ZXR(REF-IDX) * DY + ZYR(REF-IDX) * DX)
            + 2 * DX * DY * TA * TB + D0Y
        MOVE DXN TO DX
        ADD 1 TO REF-IDX
        SET ITER UP BY 1
        IF RDX > RLIM OR RDX < RNLIM OR RDY > RLIM OR RDY < RNLIM
            PERFORM DELTA-RESCALE
        ELSE
            IF RZMAGR(REF-IDX) <= RZLIM
                PERFORM DELTA-REBASE
            END-IF
        END-IF
    END-PERFORM.

    IF DELTA-DONE = 0 AND ITER < MAX-ITER-IDX
        *> The reference is about to escape. Rather than assume
        *> the pixel escapes on the same iteration, hand it to the
        *> direct loop one step early; it is within ~1e-8 of the
        *> reference so 16 decimals settle the last step exactly.
        PERFORM DELTA-EXIT
    END-IF.
    IF DELTA-DONE = 1
        PERFORM STANDARD-LOOP
    ELSE
        SET ITER-RESULT TO ITER
    END-IF.

DELTA-EXIT.
    COMPUTE FZX = ZXR(REF-IDX) + DX * TA * TB.
    COMPUTE FZY = ZYR(REF-IDX) + DY * TA * TB.
    COMPUTE FZX2 = FZX * FZX.
    COMPUTE FZY2 = FZY * FZY.
    MOVE Z-PAIR TO Z-CHECK-PAIR.
    SET NEXT-CHECK TO ITER.
    SET NEXT-CHECK UP BY 8.
    MOVE 1 TO DELTA-DONE.
    ADD 1 TO DELTA-EXITS.

DELTA-RESCALE.
    *> D has grown past 100. Either drop k by K-STEP, or, if k
    *> is already small, hand the point to the direct loop.
    IF K-CUR <= K-EXIT
        PERFORM DELTA-EXIT
    ELSE
        *> drop k by up to K-STEP, but never below K-EXIT
        COMPUTE K-DROP = K-CUR - K-EXIT
        IF K-DROP > K-STEP
            MOVE K-STEP TO K-DROP
        END-IF
        SUBTRACT K-DROP FROM K-CUR
        MOVE TA-TAB(K-DROP + 1) TO RESCALE-FACTOR
        COMPUTE DX = DX * RESCALE-FACTOR
        COMPUTE DY = DY * RESCALE-FACTOR
        COMPUTE D0X = D0X * RESCALE-FACTOR
        COMPUTE D0Y = D0Y * RESCALE-FACTOR
        MOVE TA-TAB(K-CUR + 1) TO TA
        MOVE TB-TAB(K-CUR + 1) TO TB
        MOVE ZLIM-TAB(K-CUR + 1) TO ZLIM
    END-IF.

DELTA-REBASE.
    *> |Z_n| is small enough that |Z_n + delta| < |delta| is
    *> possible: check it exactly, in D units, using the full-
    *> precision Z, and if so restart on the orbit from Z_0.
    *> The test is a single conditional expression so that it is
    *> evaluated entirely inside the decimal engine: Z * 10^k can
    *> be far larger than any COMP-5 field here would hold (the
    *> prefilter only bounds it loosely for k >= 11). Only when
    *> the test passes is |Z * 10^k + D| < |D| <= 141 stored.
    IF (HP-ZXR(REF-IDX) * TENK-TAB(K-CUR + 1) + DX)
       * (HP-ZXR(REF-IDX) * TENK-TAB(K-CUR + 1) + DX)
       + (HP-ZYR(REF-IDX) * TENK-TAB(K-CUR + 1) + DY)
       * (HP-ZYR(REF-IDX) * TENK-TAB(K-CUR + 1) + DY)
       < DX * DX + DY * DY
        COMPUTE ZTX = HP-ZXR(REF-IDX) * TENK-TAB(K-CUR + 1) + DX
        COMPUTE ZTY = HP-ZYR(REF-IDX) * TENK-TAB(K-CUR + 1) + DY
        MOVE ZTX TO DX
        MOVE ZTY TO DY
        MOVE 1 TO REF-IDX
        ADD 1 TO REBASES
    END-IF.

*> ------------------------------------------------------------
*> Symmetry and output
*> ------------------------------------------------------------
MIRROR-ROWS.
    COMPUTE FILL-ROW-BYTES = RENDER-WIDTH * 4.
    PERFORM VARYING PY FROM 1 BY 1 UNTIL PY > REGION-HEIGHT
        COMPUTE P-OFF = ROW-BASE-TAB(PY) * 4 + 1
        COMPUTE P-OFF2 = ROW-BASE-TAB(RENDER-HEIGHT + 1 - PY) * 4 + 1
        MOVE ITER-BUF-B(P-OFF:FILL-ROW-BYTES)
          TO ITER-BUF-B(P-OFF2:FILL-ROW-BYTES)
    END-PERFORM.

BLIT-FRAME.
    OPEN OUTPUT FRAMEBUFFER.
    IF FB-STATUS NOT = "00"
        DISPLAY "Could not open framebuffer " FUNCTION TRIM(FB-PATH)
            " - status " FB-STATUS
        STOP RUN
    END-IF.

    MOVE 1 TO P-IDX.
    MOVE 0 TO ROWS-WRITTEN.
    PERFORM VARYING BLIT-ROW FROM 1 BY 1 UNTIL BLIT-ROW > RENDER-HEIGHT
        IF RENDER-SCALE = 1
            PERFORM VARYING BLIT-COL FROM 1 BY 1
                    UNTIL BLIT-COL > SCREEN-WIDTH
                MOVE PAL-BY-ITER(ITER-CELL(P-IDX) + 2)
                  TO FB-PIXEL(BLIT-COL)
                ADD 1 TO P-IDX
            END-PERFORM
            WRITE FB-ROW
        ELSE
            MOVE 1 TO OUT-COL
            PERFORM VARYING BLIT-COL FROM 1 BY 1
                    UNTIL BLIT-COL > RENDER-WIDTH
                PERFORM RENDER-SCALE TIMES
                    IF OUT-COL <= SCREEN-WIDTH
                        MOVE PAL-BY-ITER(ITER-CELL(P-IDX) + 2)
                          TO FB-PIXEL(OUT-COL)
                    END-IF
                    ADD 1 TO OUT-COL
                END-PERFORM
                ADD 1 TO P-IDX
            END-PERFORM
            PERFORM RENDER-SCALE TIMES
                IF ROWS-WRITTEN < SCREEN-HEIGHT
                    WRITE FB-ROW
                    ADD 1 TO ROWS-WRITTEN
                END-IF
            END-PERFORM
        END-IF
    END-PERFORM.

    CLOSE FRAMEBUFFER.

*> MB_DUMP: iteration counts as text, for tests/verify.py.
*> Header: width height max-iter scale center-x center-y
*> half-width; then one count per line, row-major, top row first.
DUMP-ITERATIONS.
    OPEN OUTPUT DUMPFILE.
    IF DUMP-STATUS NOT = "00"
        DISPLAY "Could not open dump file " FUNCTION TRIM(DUMP-PATH)
            " - status " DUMP-STATUS
        EXIT PARAGRAPH
    END-IF.
    MOVE RENDER-WIDTH TO NUM-OUT.
    MOVE RENDER-HEIGHT TO NUM-OUT2.
    MOVE CURRENT-MAX-ITER TO NUM-OUT3.
    MOVE RENDER-SCALE TO NUM-OUT4.
    MOVE SPACES TO DUMP-REC.
    STRING FUNCTION TRIM(NUM-OUT) " " FUNCTION TRIM(NUM-OUT2) " "
        FUNCTION TRIM(NUM-OUT3) " " FUNCTION TRIM(NUM-OUT4) " "
        HP-CENTER-X-B(1:1) HP-CENTER-X-B(2:2) "."
        HP-CENTER-X-B(4:36) " "
        HP-CENTER-Y-B(1:1) HP-CENTER-Y-B(2:2) "."
        HP-CENTER-Y-B(4:36) " "
        HP-HALF-WIDTH-B(2:2) "." HP-HALF-WIDTH-B(4:36)
        DELIMITED BY SIZE INTO DUMP-REC
    END-STRING.
    WRITE DUMP-REC.
    COMPUTE P-LEN = RENDER-WIDTH * RENDER-HEIGHT.
    PERFORM VARYING P-IDX FROM 1 BY 1 UNTIL P-IDX > P-LEN
        MOVE ITER-CELL(P-IDX) TO NUM-OUT
        MOVE FUNCTION TRIM(NUM-OUT) TO DUMP-REC
        WRITE DUMP-REC
    END-PERFORM.
    CLOSE DUMPFILE.

*> ------------------------------------------------------------
*> Keyboard
*> ------------------------------------------------------------
READ-KEY.
    MOVE SPACE TO WS-KEY.
    MOVE 0 TO WS-CRT-STATUS.
    IF SCRIPTED
        PERFORM SCRIPT-NEXT-KEY
    ELSE
        ACCEPT WS-KEY LINE 1 COLUMN 1 WITH AUTO NO-ECHO END-ACCEPT
    END-IF.

POLL-KEY.
    MOVE LOW-VALUE TO WS-KEY.
    MOVE 0 TO WS-CRT-STATUS.
    ACCEPT WS-KEY LINE 1 COLUMN 1 WITH AUTO NO-ECHO
        TIME-OUT AFTER TIMEOUT-TICKS
    END-ACCEPT.

SCRIPT-NEXT-KEY.
    ADD 1 TO SCRIPT-POS.
    IF SCRIPT-POS > 1024 OR SCRIPT-KEYS(SCRIPT-POS:1) = SPACE
        MOVE "q" TO WS-KEY
        EXIT PARAGRAPH
    END-IF.
    EVALUATE SCRIPT-KEYS(SCRIPT-POS:1)
        WHEN "U" MOVE COB-SCR-KEY-UP    TO WS-CRT-STATUS
        WHEN "D" MOVE COB-SCR-KEY-DOWN  TO WS-CRT-STATUS
        WHEN "L" MOVE COB-SCR-KEY-LEFT  TO WS-CRT-STATUS
        WHEN "R" MOVE COB-SCR-KEY-RIGHT TO WS-CRT-STATUS
        WHEN OTHER MOVE SCRIPT-KEYS(SCRIPT-POS:1) TO WS-KEY
    END-EVALUATE.

CLASSIFY-KEY.
    MOVE 0 TO REAL-KEY-FLAG.
    EVALUATE TRUE
        WHEN WS-CRT-STATUS = COB-SCR-KEY-UP
        WHEN WS-CRT-STATUS = COB-SCR-KEY-DOWN
        WHEN WS-CRT-STATUS = COB-SCR-KEY-LEFT
        WHEN WS-CRT-STATUS = COB-SCR-KEY-RIGHT
        WHEN WS-KEY = "w" OR WS-KEY = "W"
        WHEN WS-KEY = "s" OR WS-KEY = "S"
        WHEN WS-KEY = "a" OR WS-KEY = "A"
        WHEN WS-KEY = "d" OR WS-KEY = "D"
        WHEN WS-KEY = "+" OR WS-KEY = "="
        WHEN WS-KEY = "-"
        WHEN WS-KEY = "[" OR WS-KEY = "]"
        WHEN WS-KEY = "c" OR WS-KEY = "C"
        WHEN WS-KEY = "r" OR WS-KEY = "R"
        WHEN WS-KEY = "q" OR WS-KEY = "Q"
            MOVE 1 TO REAL-KEY-FLAG
        WHEN OTHER
            CONTINUE
    END-EVALUATE.

HANDLE-KEY.
    EVALUATE TRUE
        WHEN WS-CRT-STATUS = COB-SCR-KEY-UP
            SUBTRACT HP-PAN-STEP-Y FROM HP-CENTER-Y
        WHEN WS-CRT-STATUS = COB-SCR-KEY-DOWN
            ADD HP-PAN-STEP-Y TO HP-CENTER-Y
        WHEN WS-CRT-STATUS = COB-SCR-KEY-LEFT
            SUBTRACT HP-PAN-STEP-X FROM HP-CENTER-X
        WHEN WS-CRT-STATUS = COB-SCR-KEY-RIGHT
            ADD HP-PAN-STEP-X TO HP-CENTER-X
        WHEN WS-KEY = "w" OR WS-KEY = "W"
            SUBTRACT HP-PAN-STEP-Y FROM HP-CENTER-Y
        WHEN WS-KEY = "s" OR WS-KEY = "S"
            ADD HP-PAN-STEP-Y TO HP-CENTER-Y
        WHEN WS-KEY = "a" OR WS-KEY = "A"
            SUBTRACT HP-PAN-STEP-X FROM HP-CENTER-X
        WHEN WS-KEY = "d" OR WS-KEY = "D"
            ADD HP-PAN-STEP-X TO HP-CENTER-X
        WHEN WS-KEY = "+" OR WS-KEY = "="
            COMPUTE HP-HALF-WIDTH = HP-HALF-WIDTH * 0.8
        WHEN WS-KEY = "-"
            COMPUTE HP-HALF-WIDTH = HP-HALF-WIDTH * 1.25
        WHEN WS-KEY = "["
            IF ITER-MULT-NUM > 1
                COMPUTE ITER-MULT-NUM = ITER-MULT-NUM / 2
            END-IF
        WHEN WS-KEY = "]"
            IF ITER-MULT-NUM < 256
                COMPUTE ITER-MULT-NUM = ITER-MULT-NUM * 2
            END-IF
        WHEN WS-KEY = "c" OR WS-KEY = "C"
            COMPUTE PAL-STRETCH = PAL-STRETCH * 2
            IF PAL-STRETCH > 16
                MOVE 1 TO PAL-STRETCH
            END-IF
            PERFORM BUILD-PALETTE-CYCLE
        WHEN WS-KEY = "r" OR WS-KEY = "R"
            PERFORM FULL-RENDER
        WHEN WS-KEY = "q" OR WS-KEY = "Q"
            MOVE 1 TO QUIT-FLAG
        WHEN OTHER
            CONTINUE
    END-EVALUATE.
    PERFORM CLAMP-VIEWPORT.

CLAMP-VIEWPORT.
    IF HP-HALF-WIDTH < MIN-HALF-WIDTH
        MOVE MIN-HALF-WIDTH TO HP-HALF-WIDTH
    END-IF.
    IF HP-HALF-WIDTH > MAX-HALF-WIDTH
        MOVE MAX-HALF-WIDTH TO HP-HALF-WIDTH
    END-IF.
    IF HP-CENTER-X > MAX-CENTER
        MOVE MAX-CENTER TO HP-CENTER-X
    END-IF.
    IF HP-CENTER-X < - MAX-CENTER
        COMPUTE HP-CENTER-X = - MAX-CENTER
    END-IF.
    IF HP-CENTER-Y > MAX-CENTER
        MOVE MAX-CENTER TO HP-CENTER-Y
    END-IF.
    IF HP-CENTER-Y < - MAX-CENTER
        COMPUTE HP-CENTER-Y = - MAX-CENTER
    END-IF.

FULL-RENDER.
    PERFORM SHOW-LOCATION.
    MOVE FULL-MAX-ITER TO NUM-OUT.
    DISPLAY "Rendering full resolution, "
        FUNCTION TRIM(NUM-OUT) " iterations max"
        " (any key aborts)...".
    MOVE 1 TO RENDER-SCALE.
    PERFORM COMPUTE-VIEWPORT.
    PERFORM RENDER-FRAME.
    IF GOT-MIDFRAME-INPUT
        DISPLAY "Full-res render aborted."
    ELSE
        PERFORM SHOW-FRAME-STATS
        DISPLAY "Press any key to continue (q quits)."
        PERFORM READ-KEY
        IF WS-KEY = "q" OR WS-KEY = "Q"
            MOVE 1 TO QUIT-FLAG
        END-IF
    END-IF.
    *> Swallow that key - it meant "back to the preview".
    MOVE SPACE TO WS-KEY.
    MOVE 0 TO WS-CRT-STATUS.
    MOVE 0 TO GOT-INPUT-FLAG.

SHOW-FRAME-STATS.
    MOVE RENDER-WIDTH TO NUM-OUT.
    MOVE RENDER-HEIGHT TO NUM-OUT2.
    MOVE CURRENT-MAX-ITER TO NUM-OUT3.
    MOVE FRAME-MS TO NUM-OUT4.
    DISPLAY FUNCTION TRIM(NUM-OUT) "x" FUNCTION TRIM(NUM-OUT2)
        " @ " FUNCTION TRIM(NUM-OUT3) " iter: "
        FUNCTION TRIM(NUM-OUT4) " ms, " NO ADVANCING.
    MOVE PIXELS-COMPUTED TO NUM-OUT.
    MOVE PIXELS-FILLED TO NUM-OUT2.
    MOVE RECTS-DONE TO NUM-OUT3.
    DISPLAY FUNCTION TRIM(NUM-OUT) " pixels iterated, "
        FUNCTION TRIM(NUM-OUT2) " filled, "
        FUNCTION TRIM(NUM-OUT3) " rectangles" NO ADVANCING.
    IF PERTURB
        MOVE ORBIT-LEN TO NUM-OUT
        MOVE K0 TO NUM-OUT2
        MOVE REBASES TO NUM-OUT3
        MOVE DELTA-EXITS TO NUM-OUT4
        DISPLAY "; perturbation: ref orbit "
            FUNCTION TRIM(NUM-OUT) " pts, k0=" FUNCTION TRIM(NUM-OUT2)
            ", " FUNCTION TRIM(NUM-OUT3) " rebases, "
            FUNCTION TRIM(NUM-OUT4) " direct exits" NO ADVANCING
    END-IF.
    DISPLAY ".".

*> ------------------------------------------------------------
*> Palette
*> ------------------------------------------------------------
LOAD-PALETTE.
    MOVE  25 TO PAL-RED(1)   MOVE  7 TO PAL-GREEN(1)   MOVE  26 TO PAL-BLUE(1)
    MOVE   9 TO PAL-RED(2)   MOVE  1 TO PAL-GREEN(2)   MOVE  47 TO PAL-BLUE(2)
    MOVE   4 TO PAL-RED(3)   MOVE  4 TO PAL-GREEN(3)   MOVE  73 TO PAL-BLUE(3)
    MOVE   0 TO PAL-RED(4)   MOVE  7 TO PAL-GREEN(4)   MOVE 100 TO PAL-BLUE(4)
    MOVE  12 TO PAL-RED(5)   MOVE 44 TO PAL-GREEN(5)   MOVE 138 TO PAL-BLUE(5)
    MOVE  24 TO PAL-RED(6)   MOVE 82 TO PAL-GREEN(6)   MOVE 177 TO PAL-BLUE(6)
    MOVE  57 TO PAL-RED(7)   MOVE 125 TO PAL-GREEN(7)  MOVE 209 TO PAL-BLUE(7)
    MOVE 134 TO PAL-RED(8)   MOVE 181 TO PAL-GREEN(8)  MOVE 229 TO PAL-BLUE(8)
    MOVE 211 TO PAL-RED(9)   MOVE 236 TO PAL-GREEN(9)  MOVE 248 TO PAL-BLUE(9)
    MOVE 241 TO PAL-RED(10)  MOVE 233 TO PAL-GREEN(10) MOVE 191 TO PAL-BLUE(10)
    MOVE 248 TO PAL-RED(11)  MOVE 201 TO PAL-GREEN(11) MOVE  95 TO PAL-BLUE(11)
    MOVE 255 TO PAL-RED(12)  MOVE 170 TO PAL-GREEN(12) MOVE   0 TO PAL-BLUE(12)
    MOVE 204 TO PAL-RED(13)  MOVE 128 TO PAL-GREEN(13) MOVE   0 TO PAL-BLUE(13)
    MOVE 153 TO PAL-RED(14)  MOVE  87 TO PAL-GREEN(14) MOVE   0 TO PAL-BLUE(14)
    MOVE 106 TO PAL-RED(15)  MOVE  52 TO PAL-GREEN(15) MOVE   3 TO PAL-BLUE(15)
    MOVE  66 TO PAL-RED(16)  MOVE  30 TO PAL-GREEN(16) MOVE  15 TO PAL-BLUE(16)
    *> entry 17 = entry 1, so interpolation wraps round
    MOVE PAL-ENTRY(1) TO PAL-ENTRY(17)
    PERFORM BUILD-PALETTE-CYCLE.

BUILD-PALETTE-CYCLE.
    *> PAL-CYCLE(i) for i = 1 .. 16 * stretch: linear blend from
    *> anchor a to anchor a + 1, pre-packed as BGRA.
    COMPUTE PAL-CYCLE-LEN = 16 * PAL-STRETCH.
    PERFORM VARYING PAL-I FROM 0 BY 1 UNTIL PAL-I >= PAL-CYCLE-LEN
        DIVIDE PAL-I BY PAL-STRETCH GIVING PAL-A REMAINDER PAL-T
        ADD 1 TO PAL-A
        COMPUTE PAL-C = PAL-BLUE(PAL-A)
            + (PAL-BLUE(PAL-A + 1) - PAL-BLUE(PAL-A)) * PAL-T / PAL-STRETCH
        MOVE PAL-C TO PB-BLUE
        COMPUTE PAL-C = PAL-GREEN(PAL-A)
            + (PAL-GREEN(PAL-A + 1) - PAL-GREEN(PAL-A)) * PAL-T / PAL-STRETCH
        MOVE PAL-C TO PB-GREEN
        COMPUTE PAL-C = PAL-RED(PAL-A)
            + (PAL-RED(PAL-A + 1) - PAL-RED(PAL-A)) * PAL-T / PAL-STRETCH
        MOVE PAL-C TO PB-RED
        MOVE 0 TO PB-ALPHA
        MOVE PIXEL-BUILD TO PAL-CYCLE(PAL-I + 1)
    END-PERFORM.
