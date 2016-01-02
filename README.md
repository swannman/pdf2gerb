# pdf2gerb
Perl script converts PDF files to Gerber format

Pdf2Gerb generates Gerber 274X photoplotting and Excellon drill files from PDFs of a PCB.  Up to three PDFs are used: the top copper layer, the bottom copper layer (for 2-sided PCBs), and an optional silk screen layer.  The PDFs can be created directly from any PDF drawing software, or a PDF print driver can be used to capture the Print output if the drawing software does not directly support output to PDF.

The general workflow is as follows:
1. Design the PCB using your favorite CAD or drawing software.
2. Print the top and bottom copper and top silk screen layers to a PDF file.
3. Run Pdf2Gerb on the PDFs to create Gerber and Excellon files.
4. Use a Gerber viewer to double-check the output against the original PCB design.
5. Make adjustments as needed.
6. Submit the files to a PCB manufacturer.

Please note that Pdf2Gerb does NOT perform DRC (Design Rule Checks), as these will vary according to individual PCB manufacturer conventions and capabilities.  Also note that Pdf2Gerb is not perfect, so the output files must always be checked before submitting them.  As of version 1.6, Pdf2Gerb supports most PCB elements, such as round and square pads, round holes, traces, SMD pads, ground planes, no-fill areas, and panelization.  However, because it interprets the graphical output of a Print function, there are limitations in what it can recognize (or there may be bugs).

See docs/Pdf2Gerb.pdf for install/setup, config, usage, and other info.
