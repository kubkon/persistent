{-# LANGUAGE OverloadedStrings, QuasiQuotes, TemplateHaskell, TypeFamilies, GADTs #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FlexibleInstances, MultiParamTypeClasses #-}
import Test.Hspec
import Test.Hspec.QuickCheck
import Data.ByteString.Lazy.Char8 ()
import Test.QuickCheck.Arbitrary
import Control.Applicative ((<$>), (<*>), Const (..))
import Data.Functor.Identity (Identity (..))

import Database.Persist
import Database.Persist.TH
import Database.Persist.Types (PersistValue(..))
import Data.Text (Text, pack)
import Data.Aeson

share [mkPersist sqlSettings { mpsGeneric = False }, mkDeleteCascade sqlSettings { mpsGeneric = False }] [persistUpperCase|
Person json
    name Text
    age Int Maybe
    address Address
    deriving Show Eq
Address json
    street Text
    city Text
    zip Int Maybe
    deriving Show Eq
NoJson
    foo Text
    deriving Show Eq
|]

share [mkPersist sqlSettings { mpsGeneric = False, mpsGenerateLenses = True }] [persistLowerCase|
Lperson json
    name Text
    age Int Maybe
    address Laddress
    deriving Show Eq
Laddress json
    street Text
    city Text
    zip Int Maybe
    deriving Show Eq
|]

share [mkPersist sqlSettings { mpsGeneric = True , mpsGenerateLenses = True }] [persistLowerCase|
Foo
    bar Text Maybe
    baz BazId
Baz
    bin Int
|]

-- ensure no-json works
instance ToJSON NoJson where
    toJSON = undefined
instance FromJSON NoJson where
    parseJSON = undefined

arbitraryT = pack <$> arbitrary

instance Arbitrary Person where
    arbitrary = Person <$> arbitraryT <*> arbitrary <*> arbitrary
instance Arbitrary Address where
    arbitrary = Address <$> arbitraryT <*> arbitraryT <*> arbitrary

main :: IO ()
main = hspec $ do
    describe "JSON serialization" $ do
        prop "to/from is idempotent" $ \person ->
            decode (encode person) == Just (person :: Person)
        it "decode" $
            decode "{\"name\":\"Michael\",\"age\":27,\"address\":{\"street\":\"Narkis\",\"city\":\"Maalot\"}}" `shouldBe` Just
                (Person "Michael" (Just 27) $ Address "Narkis" "Maalot" Nothing)
    describe "JSON serialization for Entity" $ do
        let key = Key (PersistInt64 0)
        prop "to/from is idempotent" $ \person ->
            decode (encode (Entity key person)) == Just (Entity key (person :: Person))
        it "decode" $
            decode "{\"key\": 0, \"value\": {\"name\":\"Michael\",\"age\":27,\"address\":{\"street\":\"Narkis\",\"city\":\"Maalot\"}}}" `shouldBe` Just
                (Entity key (Person "Michael" (Just 27) $ Address "Narkis" "Maalot" Nothing))
    it "lens operations" $ do
        let street1 = "street1"
            city1 = "city1"
            city2 = "city2"
            zip1 = Just 12345
            address1 = Laddress street1 city1 zip1
            address2 = Laddress street1 city2 zip1
            name1 = "name1"
            age1 = Just 27
            person1 = Lperson name1 age1 address1
            person2 = Lperson name1 age1 address2
        (person1 ^. lpersonAddress) `shouldBe` address1
        (person1 ^. (lpersonAddress . laddressCity)) `shouldBe` city1
        (person1 & ((lpersonAddress . laddressCity) .~ city2)) `shouldBe` person2

x & f = f x

(^.) :: s
     -> ((a -> Const a b) -> (s -> Const a t))
     -> a
x ^. lens = getConst $ lens Const x

(.~) :: ((a -> Identity b) -> (s -> Identity t))
     -> b
     -> s
     -> t
lens .~ val = runIdentity . lens (\_ -> Identity val)
