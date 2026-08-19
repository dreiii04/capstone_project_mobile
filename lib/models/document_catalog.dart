class DocumentOption {
  final String name;
  final double price;

  const DocumentOption(this.name, this.price);
}

const List<DocumentOption> documentOptions = [
  DocumentOption('F-137 (SH)', 400),
  DocumentOption('F-137 (GS/JH)', 250),
  DocumentOption('Transcript of Records (TOR)', 600),
  DocumentOption('General Weighted Average (GWA)', 250),
  DocumentOption('Good Moral Character/ESC (GMC/ESC)', 200),
  DocumentOption('Card (re-print)', 200),
  DocumentOption('MOI (Memorandum of Inclusion)', 250),
  DocumentOption('Student Verification', 250),
  DocumentOption('Request Form (Lost)', 200),
  DocumentOption('Certified True Copy (CTC)', 200),
  DocumentOption('Diploma (2nd Copy)', 300),
  DocumentOption('Application for Graduation', 200),
  DocumentOption('Prospectus', 200),
  DocumentOption('Certificate of Grades', 250),
  DocumentOption('Transfer Credential', 300),
  DocumentOption('Certificate of Enrollment', 250),
  DocumentOption('Clearance', 200),
  DocumentOption('Others', 0),
];

double documentPriceForName(String name) {
  final normalized = name.trim().toLowerCase();
  for (final option in documentOptions) {
    if (option.name.toLowerCase() == normalized) return option.price;
  }
  return 0;
}
