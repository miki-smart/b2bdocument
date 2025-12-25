# 🎨 UI Design Generation Prompt (for Stitch/v0/Figma AI)

**Goal:** Generate a complete, high-fidelity UI design system for the **Movello B2B Mobility Marketplace**.
**Style:** Professional, Trust-Centric, Clean B2B Aesthetic.
**Framework:** Tailwind CSS + Shadcn/UI style.
**Theme:**
-   **Primary:** Blue-600 (`#2563EB`)
-   **Sidebar:** Dark Navy (`#1E293B`)
-   **Background:** Light Gray (`#F9FAFB`)
-   **Font:** Inter

---

## 📋 Instructions for AI Designer

1.  **Strict Ordering:** Generate designs **Portal by Portal** in the exact logical order listed below. Do not jump between portals.
2.  **Visual Consistency:** Maintain the same header, sidebar, and card styling across all pages.
3.  **Data Accuracy:** Use the specific field names and control types listed for each form.
4.  **Action Clarity:** Label buttons exactly as specified (e.g., "Publish RFQ" not just "Submit").

---

## 🏢 PART 1: BUSINESS PORTAL (Generate First)

### 1. Business Dashboard
-   **Layout:** Sidebar Left, Header Top.
-   **Cards:**
    -   "Active RFQs" (Count: 5, Icon: FileText, Color: Blue)
    -   "Ongoing Contracts" (Count: 3, Icon: Briefcase, Color: Green)
    -   "Wallet Balance" (Amount: ETB 124,500, Icon: Wallet, Color: Orange)
-   **Table:** "Recent Activity" showing columns: Date, Activity Type, Details, Status.

### 2. Create RFQ - Step 1 (Basic Details)
-   **Context:** Form to start a new request.
-   **Fields:**
    -   `RFQ Title` (Input Text)
    -   `Description` (Textarea)
    -   `Start Date` & `End Date` (Date Range Picker)
    -   `Bid Deadline` (Date Time Picker) - *Note: Must be before Start Date*
    -   `Location` (Select Dropdown: Addis Ababa, Dire Dawa, etc.)
-   **Actions:** "Cancel" (Gray Ghost), "Next Step" (Blue Solid).

### 3. Create RFQ - Step 2 (Line Items)
-   **Context:** Adding vehicles to the request.
-   **Left Panel (List):**
    -   Card showing: "1. EV Sedan" | Qty: 5 | With Driver | Tags: [Luxury]
    -   "Add Line Item" Form:
        -   `Vehicle Type` (Select: EV Sedan, SUV, Minibus)
        -   `Quantity` (Number Input)
        -   `With Driver` (Switch/Toggle)
        -   `Tags` (Multi-select Chips)
        -   Button: "+ Add Item" (Outline)
-   **Right Panel (Summary):** Sticky card showing Title, Dates, Total Vehicles.
-   **Actions:** "Back" (Gray), "Save Draft" (Outline), "Publish RFQ" (Blue Solid).

### 4. RFQ Detail View (Business)
-   **Header:** Title, Status Badge (PUBLISHED), "Cancel RFQ" (Red Outline).
-   **Content:**
    -   Info Cards: Duration, Location, Total Items.
    -   "Line Items" Table: Type, Qty, Driver, Tags.
    -   **Bids Section:** Banner "3 Bids Received" with button "Review Bids".

### 5. Bid Review & Award (CRITICAL)
-   **Layout:** Tabbed view by Line Item (e.g., "Item 1: EV Sedan").
-   **Table:**
    -   `Select` (Checkbox)
    -   `Provider` (Text: "Provider •••4411")
    -   `Qty Offered` (Number)
    -   `Unit Price` (Text: ETB 3,500)
    -   `Total` (Text: ETB 17,500)
    -   `Trust Score` (Badge: 98/100 Green)
-   **Bottom Bar:**
    -   Text: "Total Escrow Required: ETB 25,500"
    -   Button: "Award Selected Bids" (Blue Solid).

### 6. Contract Detail View
-   **Header:** Contract # (CNT-2025-001), Status (ACTIVE).
-   **Content:**
    -   "Terms & Conditions" (Scrollable text box).
    -   "Assigned Vehicles" Table: Plate #, Driver Name, Phone.
-   **Actions:** "Request Early Return" (Red Outline), "Download PDF" (Gray Outline).

---

## 🚛 PART 2: PROVIDER PORTAL (Generate Second)

### 7. Provider Dashboard
-   **Cards:**
    -   "Active Contracts" (Count: 2)
    -   "Fleet Status" (Pie Chart: 5 Active, 2 Assigned)
    -   "Wallet Balance" (ETB 45,000)
    -   "Trust Score" (Gauge: 85%)

### 8. Marketplace (RFQ List)
-   **Style:** Grid of Cards (3 columns).
-   **Sidebar Filters:**
    -   `Vehicle Type` (Checkbox List)
    -   `Duration` (Radio: Short/Long)
    -   `Location` (Select)
-   **Card Content:**
    -   Title, Date Range.
    -   Line Items Summary (Icons + Text).
    -   "3 Bids" Badge.
    -   **Actions:** "Bid Now" (Blue Solid), Bookmark Icon.

### 9. RFQ Detail & Bidding
-   **Layout:** Split Screen.
-   **Left (Info):** RFQ Details, Business Name, Trust Score.
-   **Right (Form):**
    -   Header: "Submit Bid for Item 1".
    -   `Quantity Offered` (Number Input, Max: 5).
    -   `Unit Price` (Number Input, Suffix: ETB).
    -   `Notes` (Textarea).
    -   **Total Calculation:** "Total Bid: ETB 17,500".
    -   **Action:** "Submit Bid" (Blue Solid).

### 10. Vehicle Registration
-   **Stepper:** 1. Info -> 2. Insurance -> 3. Photos.
-   **Form Fields:**
    -   `Plate Number` (Input)
    -   `Make/Model` (Input)
    -   `Year` (Select)
    -   `Insurance Policy #` (Input)
    -   `Expiry Date` (Date Picker)
-   **Photo Upload:** Grid of 5 boxes (Front, Back, Left, Right, Interior) with "+" icons.

### 11. Vehicle Assignment
-   **Layout:** Split View.
-   **Left (Required):** List of required items with progress bars (e.g., "EV Sedan: 3/5 assigned").
-   **Right (Available Fleet):**
    -   List of vehicle cards.
    -   `Select` (Checkbox).
    -   Details: Plate #, Model.
-   **Action:** "Assign Selected" (Blue Solid).

### 12. Delivery OTP Verification
-   **Layout:** Centered Card.
-   **Content:**
    -   Header: "Verify Delivery".
    -   Instruction: "Enter 6-digit code from business".
    -   Input: 6 large boxes.
    -   Timer: "Expires in 4:59".
-   **Action:** "Verify Code" (Blue Solid).

---

## 💰 PART 3: FINANCE & WALLET (Generate Third)

### 13. Wallet Dashboard
-   **Cards:**
    -   "Total Balance" (Gray).
    -   "Available" (Green Text).
    -   "Locked/Escrow" (Orange Text).
-   **Transaction Table:**
    -   Cols: Date, Type (Badge: Deposit/Escrow/Refund), Amount (+/- Green/Red), Status.
-   **Action:** "Deposit Funds" (Blue Solid, Top Right).

### 14. Deposit Modal
-   **Content:**
    -   `Amount` (Input Number, Prefix: ETB).
    -   `Payment Method` (Radio Group: Chapa, Telebirr).
-   **Action:** "Proceed to Payment" (Blue Solid).

---

## 👤 PART 4: ADMIN PORTAL (Generate Last)

### 15. Admin Dashboard
-   **Metrics:** Total Revenue, Active Users, Pending Verifications.
-   **Chart:** Revenue over time (Line chart).

### 16. Verification Queue
-   **Tabs:** "Businesses", "Providers".
-   **Table:** Name, Type, Date Submitted, Documents (Link).
-   **Actions:** "Approve" (Green), "Reject" (Red).

---

**Design Note:** Ensure all tables have proper padding, headers have subtle gray backgrounds, and primary actions are always Blue-600 (`#2563EB`). Use Shadcn/UI "Card" component style for all containers.
