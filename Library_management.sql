-- Create the library_management database if it doesn't exist
-- This script sets up a library management system database
CREATE DATABASE IF NOT EXISTS library_management;
USE library_management;

-- Drop existing tables to ensure a clean setup
-- This is useful for development and testing purposes
DROP TABLE IF EXISTS Fines, Reservations, BorrowRecords, BookAuthors, Books, Categories, Authors, Users;

-- Table to store library members
-- This table includes the user's full name, email, phone number,
-- and the date they joined the library
-- The user_id is the primary key and auto-incremented
-- The email is unique to ensure no two users can have the same email
-- The phone number is optional
-- The membership_date is set to the current date by default
CREATE TABLE Users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20),
    membership_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table to store book authors
-- This table includes the author's name and a short biography
-- The author_id is the primary key and auto-incremented
-- The name is a string with a maximum length of 100 characters
CREATE TABLE Authors (
    author_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    bio TEXT
);

-- Table to store book categories
-- This table categorizes books into different genres
-- It includes a unique category_id and name
-- The category_id is the primary key and auto-incremented
-- The name is a string with a maximum length of 50 characters
CREATE TABLE Categories (
    category_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);

-- Table to store books
-- This table includes the book title, category, ISBN, published year,
-- and the number of copies available
CREATE TABLE Books (
    book_id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(150) NOT NULL,
    category_id INT,
    isbn VARCHAR(20) UNIQUE,
    published_year INT,
    copies_available INT DEFAULT 1,
    FOREIGN KEY (category_id) REFERENCES Categories(category_id) ON DELETE SET NULL
);

-- Junction table for many-to-many relationship between Books and Authors
CREATE TABLE BookAuthors (
    book_id INT,
    author_id INT,
    PRIMARY KEY (book_id, author_id),
    FOREIGN KEY (book_id) REFERENCES Books(book_id) ON DELETE CASCADE,
    FOREIGN KEY (author_id) REFERENCES Authors(author_id) ON DELETE CASCADE
);

-- Table to store borrowing records
-- This table records the borrowing history of books
-- It includes the user_id, book_id, borrow_date, and return_date
-- The user_id references the Users table to link borrows to specific users and
-- the book_id references the Books table to link borrows to specific books
-- The borrow_date is set to the current date by default
CREATE TABLE BorrowRecords (
    record_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    book_id INT,
    borrow_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    return_date DATE,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (book_id) REFERENCES Books(book_id) ON DELETE CASCADE
);

-- Table to store fines for late returns
-- This table records fines issued to users for overdue books
-- It includes the user_id, amount, issue_date, and a paid status
-- The user_id references the Users table to link fines to specific users
-- The amount is the fine charged for the overdue book
CREATE TABLE Fines (
    fine_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    amount DECIMAL(10,2) NOT NULL,
    issue_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    paid BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE
);

-- Table to store book reservations
-- This table allows users to reserve books that are currently unavailable
-- It includes the user_id, book_id, and reservation_date
-- The reservation_date is set to the current date by default
-- The foreign keys reference the Users and Books tables
-- to ensure data integrity
-- When a user reserves a book, it is recorded in this table
CREATE TABLE Reservations (
    reservation_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    book_id INT,
    reservation_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (book_id) REFERENCES Books(book_id) ON DELETE CASCADE
);

-- Indexes for performance
-- Indexes are created on frequently queried columns
-- to speed up search operations
CREATE INDEX idx_email ON Users(email);
CREATE INDEX idx_isbn ON Books(isbn);
CREATE INDEX idx_borrow_user ON BorrowRecords(user_id);
CREATE INDEX idx_borrow_book ON BorrowRecords(book_id);

-- Trigger. Decrease copies_available when a book is borrowed
-- This trigger will update the copies_available in Books table
-- when a new record is inserted into BorrowRecords
DELIMITER //
CREATE TRIGGER after_borrow_insert
AFTER INSERT ON BorrowRecords
FOR EACH ROW
BEGIN
    UPDATE Books
    SET copies_available = copies_available - 1
    WHERE book_id = NEW.book_id;
END //
DELIMITER ;

-- Trigger: Increase copies_available when a book is returned
-- This trigger will update the copies_available in Books table
-- when the return_date is set in BorrowRecords
-- It checks if the return_date is not NULL and the old return_date was NULL
-- to ensure it only updates when the book is actually returned
DELIMITER //
CREATE TRIGGER after_return_update
AFTER UPDATE ON BorrowRecords
FOR EACH ROW
BEGIN
    IF NEW.return_date IS NOT NULL AND OLD.return_date IS NULL THEN
        UPDATE Books
        SET copies_available = copies_available + 1
        WHERE book_id = NEW.book_id;
    END IF;
END //
DELIMITER ;

-- Trigger to add fine for overdue books assumes a 14 day borrowing period
-- and a fine of Ksh 5.00 for each overdue book
-- This trigger will insert a fine record if the book is overdue
-- and the return_date is still NULL
DELIMITER //
CREATE TRIGGER after_borrow_overdue
AFTER UPDATE ON BorrowRecords
FOR EACH ROW
BEGIN
    IF NEW.return_date IS NULL AND DATEDIFF(CURDATE(), NEW.borrow_date) > 14 THEN
        INSERT INTO Fines (user_id, amount, issue_date)
        VALUES (NEW.user_id, 5.00, CURDATE());
    END IF;
END //
DELIMITER ;

-- Stored Procedure. Borrow a book
-- This procedure checks if the book is available before allowing the borrow
-- If the book is not available, it raises an error
-- The procedure takes userId and bookId as input parameters
-- and inserts a record into BorrowRecords if the book is available
-- It also updates the copies_available in the Books table
-- to reflect the decrease in available copies
DELIMITER //
CREATE PROCEDURE BorrowBook(IN userId INT, IN bookId INT)
BEGIN
    DECLARE available INT;
    SELECT copies_available INTO available FROM Books WHERE book_id = bookId;
    IF available > 0 THEN
        INSERT INTO BorrowRecords (user_id, book_id, borrow_date)
        VALUES (userId, bookId, CURRENT_TIMESTAMP);
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Book is not available';
    END IF;
END //
DELIMITER ;

-- Stored Procedure: Return a book
-- This procedure updates the return_date in BorrowRecords
-- It checks if the record exists and if the book has not been returned yet
DELIMITER //
CREATE PROCEDURE ReturnBook(IN recordId INT)
BEGIN
    UPDATE BorrowRecords
    SET return_date = CURRENT_DATE
    WHERE record_id = recordId AND return_date IS NULL;
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid record or book already returned';
    END IF;
END //
DELIMITER ;

-- Stored Procedure: Reserve a book
-- This procedure allows a user to reserve a book
-- It checks if the book is available for reservation
-- and inserts a record into Reservations
-- It takes userId and bookId as input parameters
DELIMITER //
CREATE PROCEDURE ReserveBook(IN userId INT, IN bookId INT)
BEGIN
    INSERT INTO Reservations (user_id, book_id, reservation_date)
    VALUES (userId, bookId, CURRENT_DATE);
END //
DELIMITER ;

-- View: Active borrows
-- This view shows all active borrows
-- It includes the user's full name, book title, and borrow date
-- It joins the BorrowRecords table with Users and Books tables
-- to get the necessary information
-- It filters the records where return_date is NULL
-- indicating that the book has not been returned yet
-- The view is useful for tracking currently borrowed books
-- and the users who have borrowed them
CREATE VIEW ActiveBorrows AS
SELECT u.full_name, b.title, br.borrow_date
FROM BorrowRecords br
JOIN Users u ON br.user_id = u.user_id
JOIN Books b ON br.book_id = b.book_id
WHERE br.return_date IS NULL;

-- View: Overdue books (more than 14 days)
CREATE VIEW OverdueBooks AS
SELECT u.full_name, b.title, br.borrow_date, DATEDIFF(CURDATE(), br.borrow_date) AS days_overdue
FROM BorrowRecords br
JOIN Users u ON br.user_id = u.user_id
JOIN Books b ON br.book_id = b.book_id
WHERE br.return_date IS NULL
AND br.borrow_date < DATE_SUB(CURDATE(), INTERVAL 14 DAY);

-- View: User fines
-- This view aggregates the total fines for each user
-- It shows the user's full name, total fines amount, and the count of fines
-- It only includes unpaid fines
-- The view joins the Fines table with the Users table
-- and groups the results by user_id and full_name
CREATE VIEW UserFines AS
SELECT u.full_name, SUM(f.amount) AS total_fines, COUNT(f.fine_id) AS fine_count
FROM Fines f
JOIN Users u ON f.user_id = u.user_id
WHERE f.paid = FALSE
GROUP BY u.user_id, u.full_name;

-- Sample Data
-- Insert sample data into Users, Authors, Categories, Books, BookAuthors, BorrowRecords, Fines, Reservations
INSERT INTO Users (full_name, email, phone) VALUES
    ('John Kamau', 'k.john@gmail.com', '123-456-7890'),
    ('Mary Owiti', 'owiti.mary@gmail.com', '987-654-3210');

INSERT INTO Authors (name, bio) VALUES
    ('J.K. Rowling', 'British author, best known for Harry Potter series'),
    ('George Orwell', 'English novelist, known for 1984 and Animal Farm');

INSERT INTO Categories (name) VALUES
    ('Fantasy'),
    ('Dystopian');

INSERT INTO Books (title, category_id, isbn, published_year, copies_available) VALUES
    ('Harry Potter and the Sorcerer''s Stone', 1, '978-0439708180', 1997, 5),
    ('1984', 2, '978-0451524935', 1949, 3);

INSERT INTO BookAuthors (book_id, author_id) VALUES
    (1, 1),
    (2, 2);

INSERT INTO BorrowRecords (user_id, book_id, borrow_date) VALUES
    (1, 1, '2025-05-01'),
    (2, 2, '2025-04-20');

INSERT INTO Fines (user_id, amount, issue_date, paid) VALUES
    (2, 5.00, '2025-05-08', FALSE);

INSERT INTO Reservations (user_id, book_id, reservation_date) VALUES
    (1, 2, '2025-05-09');