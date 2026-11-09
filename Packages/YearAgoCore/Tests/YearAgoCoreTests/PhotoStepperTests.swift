import Testing
@testable import YearAgoCore

@Suite struct PhotoStepperTests {
    @Test func startsOnFirstPhoto() {
        let stepper = PhotoStepper(count: 3)
        #expect(stepper.currentIndex == 0)
        #expect(!stepper.canGoBack)
        #expect(stepper.canGoForward)
        #expect(!stepper.isAtEnd)
    }

    @Test func stepsToEndCardAndStops() {
        var stepper = PhotoStepper(count: 2)
        stepper.next()
        #expect(stepper.currentIndex == 1)
        stepper.next()
        #expect(stepper.isAtEnd)
        #expect(stepper.currentIndex == nil)
        #expect(!stepper.canGoForward)
        stepper.next()  // never wraps or leaves the year
        #expect(stepper.isAtEnd)
        stepper.previous()
        #expect(stepper.currentIndex == 1)
    }

    @Test func stopsAtFirstPhoto() {
        var stepper = PhotoStepper(count: 2)
        stepper.previous()
        #expect(stepper.currentIndex == 0)
    }

    @Test func emptyYear() {
        var stepper = PhotoStepper(count: 0)
        #expect(stepper.isEmpty)
        #expect(!stepper.isAtEnd)
        #expect(stepper.currentIndex == nil)
        stepper.next()
        stepper.previous()
        #expect(stepper.position == 0)
    }

    @Test func moveToEnd() {
        var stepper = PhotoStepper(count: 3)
        stepper.moveToEnd()
        #expect(stepper.isAtEnd)
        var empty = PhotoStepper(count: 0)
        empty.moveToEnd()
        #expect(empty.position == 0)
    }

    @Test func jumpIgnoresOutOfRange() {
        var stepper = PhotoStepper(count: 5)
        stepper.jump(to: 3)
        #expect(stepper.currentIndex == 3)
        stepper.jump(to: 5)
        stepper.jump(to: -1)
        #expect(stepper.currentIndex == 3)
    }
}
